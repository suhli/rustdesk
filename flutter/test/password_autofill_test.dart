import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/dialog.dart';
import 'package:flutter_hbb/common/widgets/login.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';

class _TestBridge implements RustdeskImpl {
  final options = <String, String>{};
  final requests = <Map<String, dynamic>>[];
  final connections = <Map<Symbol, dynamic>>[];
  bool remember = false;
  List<String> loginOptions = [];
  Map<String, dynamic> response = {'error': 'Invalid credentials'};
  Completer<String>? pendingResponse;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final args = invocation.namedArguments;
    switch (invocation.memberName) {
      case #translate:
        return args[#name];
      case #getLocalFlutterOption:
      case #mainGetOptionSync:
        return '';
      case #mainGetLocalOption:
        return options[args[#key]] ?? '';
      case #mainGetLoginDeviceInfo:
        return '{}';
      case #mainSetLocalOption:
        options[args[#key] as String] = args[#value] as String;
        return Future<void>.value();
      case #mainGetApiServer:
        return Future.value('https://console.example.test');
      case #mainGetMyId:
      case #mainGetUuid:
        return Future.value('test-device');
      case #mainGetProxyStatus:
        return Future.value(true);
      case #isDisableAb:
      case #isDisableGroupPanel:
        return true;
      case #mainHttpRequest:
        if ((args[#url] as String).endsWith('/api/login')) {
          requests.add(jsonDecode(args[#body] as String));
        }
        return Future<void>.value();
      case #mainGetHttpStatus:
        if ((args[#url] as String).endsWith('/api/login-options')) {
          return Future.value(_httpResponse(loginOptions));
        }
        return pendingResponse?.future ?? Future.value(_httpResponse(response));
      case #sessionGetRemember:
        return Future<bool?>.value(remember);
      case #sessionLogin:
        connections.add(Map.of(args));
        return Future<void>.value();
      default:
        throw UnsupportedError(
            'Unexpected bridge call: ${invocation.memberName}');
    }
  }

  String _httpResponse(Object body) => jsonEncode({
        'body': jsonEncode(body),
        'headers': {'content-type': 'application/json; charset=utf-8'},
        'status_code': 200,
      });
}

Future<void> _mount(WidgetTester tester, [Widget? child]) async {
  await tester.pumpWidget(MaterialApp(
      navigatorKey: globalKey,
      theme: ThemeData(useMaterial3: false),
      home: Scaffold(body: child ?? const SizedBox())));
}

Future<void> _fill(WidgetTester tester, Map<Finder, String> values) async {
  await tester.tap(values.keys.first);
  await tester.pump();
  final client = (tester.testTextInput.log
          .lastWhere((call) => call.method == 'TextInput.setClient')
          .arguments as List)
      .first;
  final updates = <String, dynamic>{};
  for (final entry in values.entries) {
    final editable = tester.state<EditableTextState>(
        find.descendant(of: entry.key, matching: find.byType(EditableText)));
    updates[editable.autofillId] = TextEditingValue(
            text: entry.value,
            selection: TextSelection.collapsed(offset: entry.value.length))
        .toJSON();
  }
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/textinput',
      const JSONMethodCodec().encodeMethodCall(MethodCall(
          'TextInputClient.updateEditingStateWithTag', [client, updates])),
      (_) {});
  await tester.pump();
}

Iterable<MethodCall> _finishes(WidgetTester tester) => tester.testTextInput.log
    .where((call) => call.method == 'TextInput.finishAutofillContext');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _TestBridge bridge;
  final ios = TargetPlatformVariant.only(TargetPlatform.iOS);

  setUp(() async {
    isTest = true;
    bridge = _TestBridge();
    platformFFI.ffiBind = bridge;
    await initGlobalFFI();
  });

  tearDown(() {
    isTest = false;
    Get.reset();
  });

  testWidgets(
      'Console groups both hints and autofills the original controllers',
      (tester) async {
    final username = TextEditingController();
    final password = TextEditingController();
    final focus = FocusNode();
    addTearDown(username.dispose);
    addTearDown(password.dispose);
    addTearDown(focus.dispose);
    final provider = ''.obs;
    var submitted = <String>[];
    await _mount(
        tester,
        LoginWidgetUserPass(
            username: username,
            pass: password,
            usernameMsg: null,
            passMsg: null,
            userFocusNode: focus,
            isInProgress: false,
            curOP: provider,
            onLogin: () => submitted = [username.text, password.text]));
    final fields = find.byType(TextField);
    final userField = tester.widget<TextField>(fields.at(0));
    final passField = tester.widget<TextField>(fields.at(1));
    expect(userField.autofillHints, [AutofillHints.username]);
    expect(passField.autofillHints, [AutofillHints.password]);
    expect(userField.controller, same(username));
    expect(passField.controller, same(password));
    expect(userField.focusNode, same(focus));
    expect(AutofillGroup.of(tester.element(fields.at(0))),
        same(AutofillGroup.of(tester.element(fields.at(1)))));
    await _fill(tester, {fields.at(0): 'alice', fields.at(1): 'secret'});
    await tester.tap(find.byIcon(Icons.visibility_off));
    await tester.pump();
    expect(tester.widget<TextField>(fields.at(1)).obscureText, isFalse);
    expect(tester.widget<TextField>(fields.at(1)).autofillHints,
        [AutofillHints.password]);
    await tester.tap(find.byType(ElevatedButton));
    expect(submitted, ['alice', 'secret']);
    expect(_finishes(tester), isEmpty);
    await tester.pumpWidget(const SizedBox());
    expect(_finishes(tester).map((call) => call.arguments), [false]);
  }, variant: ios);

  testWidgets('failed login retains autofilled input; successful retry commits',
      (tester) async {
    await _mount(tester);
    final result = loginDialog();
    expect(loginDialog(), same(result));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    final user = tester.widget<TextField>(fields.at(0)).controller!;
    final pass = tester.widget<TextField>(fields.at(1)).controller!;
    final group = AutofillGroup.of(tester.element(fields.at(0)));
    await _fill(tester, {fields.at(0): 'alice', fields.at(1): 'secret'});
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    expect(find.text('Invalid credentials'), findsOneWidget);
    expect([user.text, pass.text], ['alice', 'secret']);
    expect(bridge.requests.single['username'], 'alice');
    expect(bridge.requests.single['password'], 'secret');
    expect(AutofillGroup.of(tester.element(fields.at(0))), same(group));
    expect(_finishes(tester), isEmpty);
    bridge.response = {'type': 'access_token', 'access_token': 'test-token'};
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
    expect(bridge.options['access_token'], 'test-token');
    expect(_finishes(tester).where((call) => call.arguments == true),
        hasLength(1));
  }, variant: ios);

  testWidgets('cancel and reopen creates a fresh group without saving',
      (tester) async {
    await _mount(tester);
    final first = loginDialog();
    await tester.pumpAndSettle();
    await _fill(tester, {
      find.byType(TextField).at(0): 'alice',
      find.byType(TextField).at(1): 'secret'
    });
    final group =
        AutofillGroup.of(tester.element(find.byType(TextField).first));
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(await first, isFalse);
    expect(_finishes(tester).map((call) => call.arguments), [false]);
    final second = loginDialog();
    await tester.pumpAndSettle();
    expect(AutofillGroup.of(tester.element(find.byType(TextField).first)),
        isNot(same(group)));
    expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
        isEmpty);
    gFFI.dialogManager.dismissAll();
    await tester.pumpAndSettle();
    await second;
    expect(_finishes(tester).every((call) => call.arguments == false), isTrue);
  }, variant: ios);

  testWidgets(
      'editing credentials during a request does not save unverified input',
      (tester) async {
    await _mount(tester);
    final result = loginDialog();
    await tester.pumpAndSettle();
    await _fill(tester, {
      find.byType(TextField).at(0): 'alice',
      find.byType(TextField).at(1): 'secret'
    });
    bridge.pendingResponse = Completer<String>();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), 'edited');
    bridge.pendingResponse!.complete(bridge
        ._httpResponse({'type': 'access_token', 'access_token': 'test-token'}));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
    expect(bridge.requests.single['password'], 'secret');
    expect(_finishes(tester).every((call) => call.arguments == false), isTrue);
  }, variant: ios);

  testWidgets('OIDC success does not commit the account password form',
      (tester) async {
    bridge.loginOptions = ['oidc/github'];
    await _mount(tester);
    final result = loginDialog();
    await tester.pumpAndSettle();
    await _fill(tester, {
      find.byType(TextField).at(0): 'alice',
      find.byType(TextField).at(1): 'unfinished'
    });
    tester
        .widget<LoginWidgetOP>(find.byType(LoginWidgetOP))
        .cbLogin({'type': 'access_token', 'access_token': 'oidc-token'});
    await tester.pumpAndSettle();
    expect(await result, isTrue);
    expect(_finishes(tester).every((call) => call.arguments == false), isTrue);
    expect(bridge.requests, isEmpty);
  }, variant: ios);

  for (final remember in [false, true]) {
    testWidgets(
        'device password autofills existing login with remember=$remember',
        (tester) async {
      bridge.remember = remember;
      await _mount(tester);
      enterPasswordDialog(gFFI.sessionId, gFFI.dialogManager);
      await tester.pumpAndSettle();
      final field = find.byType(TextField);
      expect(field, findsOneWidget);
      expect(tester.widget<TextField>(field).autofillHints,
          [AutofillHints.password]);
      expect(
          tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
          remember);
      final password = remember ? 'Permanent-password!' : '123456';
      await _fill(tester, {field: password});
      final dialog =
          tester.widget<CustomAlertDialog>(find.byType(CustomAlertDialog));
      dialog.onSubmit!();
      await tester.pump();
      expect(bridge.connections.single[#sessionId], gFFI.sessionId);
      expect(bridge.connections.single[#password], password);
      expect(bridge.connections.single[#remember], remember);
      expect(bridge.connections.single[#osUsername], isEmpty);
      expect(bridge.connections.single[#osPassword], isEmpty);
      expect(_finishes(tester).map((call) => call.arguments), [false]);
      gFFI.dialogManager.dismissAll();
      await tester.pumpAndSettle();
    }, variant: ios);
  }

  testWidgets('combined device and OS login isolates the device autofill group',
      (tester) async {
    await _mount(tester);
    enterUserLoginAndPasswordDialog(
        gFFI.sessionId, gFFI.dialogManager, 'OS login');
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    expect(AutofillGroup.maybeOf(tester.element(fields.at(0))), isNull);
    expect(AutofillGroup.maybeOf(tester.element(fields.at(1))), isNull);
    expect(tester.widget<TextField>(fields.at(0)).autofillHints, isEmpty);
    expect(tester.widget<TextField>(fields.at(1)).autofillHints, isEmpty);
    await tester.enterText(fields.at(0), 'remote-user');
    await tester.enterText(fields.at(1), 'os-secret');
    await _fill(tester, {fields.at(2): 'device-secret'});
    tester
        .widget<CustomAlertDialog>(find.byType(CustomAlertDialog))
        .onSubmit!();
    await tester.pump();
    expect(bridge.connections.single[#osUsername], 'remote-user');
    expect(bridge.connections.single[#osPassword], 'os-secret');
    expect(bridge.connections.single[#password], 'device-secret');
    expect(_finishes(tester).map((call) => call.arguments), [false]);
    gFFI.dialogManager.dismissAll();
    await tester.pumpAndSettle();
  }, variant: ios);

  testWidgets('unspecified hints and other platforms retain their defaults',
      (tester) async {
    final username = TextEditingController();
    final password = TextEditingController();
    addTearDown(username.dispose);
    addTearDown(password.dispose);
    await _mount(
        tester,
        Column(children: [
          DialogTextField(title: 'Unrelated', controller: username),
          PasswordWidget(controller: password, autoFocus: false),
          LoginWidgetUserPass(
              username: username,
              pass: password,
              usernameMsg: null,
              passMsg: null,
              isInProgress: false,
              curOP: ''.obs,
              onLogin: () {}),
        ]));
    expect(find.byType(AutofillGroup), findsNothing);
    for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(field.autofillHints, isEmpty);
      expect(field.autocorrect, isTrue);
      expect(field.enableSuggestions, isTrue);
    }
    expect(
        tester
            .widget<PasswordWidget>(find.byType(PasswordWidget).first)
            .autofillHints,
        isNull);
    await tester.pumpWidget(const SizedBox());
    expect(_finishes(tester), isEmpty);
  },
      variant: TargetPlatformVariant(
          {TargetPlatform.android, TargetPlatform.windows}));
}
