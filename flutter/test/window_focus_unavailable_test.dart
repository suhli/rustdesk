import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/generated_bridge.dart' show RustdeskImpl;
import 'package:flutter_hbb/mobile/ios/session_toolbar.dart';
import 'package:flutter_hbb/mobile/widgets/remote_window_focus.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/window_focus_geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

class _Binding extends Fake implements RustdeskImpl {
  final activations = <String>[];

  @override
  String translate(
          {required String name, required String locale, dynamic hint}) =>
      name;

  @override
  String getLocalFlutterOption({required String k, dynamic hint}) => '';

  @override
  Future<void> sessionSendPointer(
      {required UuidValue sessionId, required String msg, dynamic hint}) async {
    final event = jsonDecode(msg);
    if (event['k'] == 'activate-remote-window') {
      activations.add(event['v'] as String);
    }
  }
}

class _Peer extends Fake implements FfiModel {
  _Peer({required bool supportsFocus, required this.keyboard}) {
    if (supportsFocus) pi.platformAdditions['remote_window_focus'] = true;
  }

  @override
  final pi = PeerInfo();
  @override
  final bool keyboard;
  @override
  bool get isPeerWindows => true;
  @override
  ValueChanged<String>? onRemoteWindows;
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

class _Canvas extends Fake implements CanvasModel {
  @override
  WindowFocusGeometry? windowFocus;
}

class _Session extends Fake implements FFI {
  _Session(this.ffiModel);

  @override
  final FfiModel ffiModel;
  @override
  final CanvasModel canvasModel = _Canvas();
  @override
  final UuidValue sessionId = const Uuid().v4obj();
}

void main() {
  late _Binding binding;
  setUp(() {
    binding = _Binding();
    platformFFI.setBindingForTesting(binding);
  });

  for (final (supportsFocus, message) in [
    (false, 'window_focus_peer_upgrade_tip'),
    (true, 'window_focus_keyboard_permission_tip'),
  ]) {
    testWidgets('window focus explains $message', (tester) async {
      final session = _Session(
          _Peer(supportsFocus: supportsFocus, keyboard: !supportsFocus));
      final focus = RemoteWindowFocus(session, onCrop: (_) {});
      addTearDown(focus.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => focus.pick(context),
            child: const Text('Focus a remote window'),
          ),
        ),
      ));

      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();

      expect(
          find.descendant(
              of: find.byType(AlertDialog), matching: find.text(message)),
          findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  }

  for (final minimized in [false, true]) {
    testWidgets(
        'iOS toolbar focuses a ${minimized ? 'minimized' : 'visible'} window '
        'and exits focus from the same button', (tester) async {
      final peer = _Peer(supportsFocus: true, keyboard: true);
      peer.pi.displays.add(Display()
        ..width = 800
        ..height = 600);
      Rect? crop;
      final focus = RemoteWindowFocus(_Session(peer), onCrop: (rect) {
        crop = rect;
      });
      addTearDown(focus.dispose);
      void ignore() {}
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: IosSessionToolbar(
            windowFocus: focus,
            touchMode: false,
            keyboardEnabled: true,
            close: ignore,
            keyboard: ignore,
            mouse: ignore,
            display: ignore,
            rotate: ignore,
            more: ignore,
            help: ignore,
            macros: ignore,
          ),
        ),
      ));
      final start = find.byTooltip('Focus a remote window');
      expect(find.byIcon(Icons.center_focus_weak), findsOneWidget);
      final position = tester.getCenter(start);
      await tester.tap(start);
      await tester.pump();

      void snapshot({required bool minimized, int x = 20}) {
        peer.onRemoteWindows!.call(jsonEncode([
          {
            'id': '100:200',
            'title': 'Remote editor',
            'app': '',
            'minimized': minimized,
            'x': x,
            'y': 30,
            'width': minimized ? 0 : 300,
            'height': minimized ? 0 : 200,
          }
        ]));
      }

      snapshot(minimized: minimized);
      await tester.pumpAndSettle();
      expect(binding.activations, isEmpty);
      await tester.tap(find.text('Remote editor'));
      await tester.pumpAndSettle();
      expect(binding.activations, ['100:200']);
      expect(crop, minimized ? null : const Rect.fromLTWH(20, 30, 300, 200));

      snapshot(minimized: false, x: 40);
      expect(crop, const Rect.fromLTWH(40, 30, 300, 200));
      expect(binding.activations, ['100:200']);
      final stop = find.byTooltip('Exit window focus');
      expect(find.byIcon(Icons.center_focus_strong), findsOneWidget);
      expect(tester.getCenter(stop), position);
      await tester.tap(stop);
      await tester.pump();
      expect(crop, isNull);
      expect(start, findsOneWidget);
      expect(find.byIcon(Icons.center_focus_weak), findsOneWidget);
      expect(binding.activations, ['100:200']);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
