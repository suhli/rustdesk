import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/mobile/ios/keyboard_macro.dart';
import 'package:flutter_hbb/mobile/ios/session_macro_menu.dart';

void main() {
  testWidgets('session menu stays compact and closes before sending the macro',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final macro = KeyboardMacro('Sleep',
        [MacroStep('Win+X', 300), MacroStep('U', 200), MacroStep('S', 0)]);
    final sent = <String>[];
    final runner = KeyboardMacroRunner(
        canSend: () => true,
        send: (key) async {
          expect(find.byType(BottomSheet), findsNothing);
          sent.add(key.label);
        });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () async {
                      final selected = await showIosSessionMacroMenu(context,
                          macros: [macro], translate: (text) => text);
                      if (selected != null) await runner.run(selected);
                    },
                    child: const Text('Open macros'))))));

    await tester.tap(find.text('Open macros'));
    await tester.pumpAndSettle();
    final sheet = tester.getRect(find.byType(BottomSheet));
    expect(sheet.bottom, 844);
    expect(sheet.height, lessThanOrEqualTo(844 * 0.4));
    expect(find.byType(Scaffold), findsOneWidget);
    expect(
        tester.widgetList<ModalBarrier>(find.byType(ModalBarrier)).every(
            (barrier) =>
                barrier.color == null || barrier.color == Colors.transparent),
        isTrue);

    await tester.tap(find.text('Sleep'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(sent, ['Win+X']);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 200));
    expect(sent, ['Win+X', 'U', 'S']);
  });

  testWidgets(
      'landscape menu scrolls and dismissing it does not select a macro',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(844, 390);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final macros = List.generate(
        20, (i) => KeyboardMacro('Macro $i', [MacroStep('A', 0)]));
    KeyboardMacro? selected;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () async {
                      selected = await showIosSessionMacroMenu(context,
                          macros: macros, translate: (text) => text);
                    },
                    child: const Text('Open macros'))))));

    await tester.tap(find.text('Open macros'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(BottomSheet)).height,
        lessThanOrEqualTo(390 * 0.4));
    await tester.scrollUntilVisible(find.text('Macro 19'), 300);
    await tester.tap(find.text('Macro 19'));
    await tester.pumpAndSettle();
    expect(selected, same(macros.last));
    expect(find.byType(BottomSheet), findsNothing);

    await tester.tap(find.text('Open macros'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(400, 40));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
