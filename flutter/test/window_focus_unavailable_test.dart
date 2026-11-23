import 'package:flutter/material.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/mobile/widgets/remote_window_focus.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/window_focus_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

class _Binding extends Fake implements RustdeskImpl {
  @override
  String translate(
          {required String name, required String locale, dynamic hint}) =>
      name;
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
}

void main() {
  setUp(() => platformFFI.setBindingForTesting(_Binding()));

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
}
