import 'package:flutter/material.dart';
import 'package:flutter_hbb/generated_bridge.dart' show RustdeskImpl;
import 'package:flutter_hbb/mobile/ios/session_toolbar.dart';
import 'package:flutter_hbb/mobile/widgets/windows_touch.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';

class _Binding extends Fake implements RustdeskImpl {
  @override
  String translate(
          {required String name, required String locale, dynamic hint}) =>
      name;
}

void main() {
  setUp(() => platformFFI.setBindingForTesting(_Binding()));

  for (final supportsNativeTouch in [true, false]) {
    testWidgets(
        'toolbar cycles pointer icons with native touch support '
        '$supportsNativeTouch', (tester) async {
      var mode = MobilePointerMode.touch;
      void ignore() {}
      await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: IosSessionToolbar(
              pointerMode: mode,
              keyboardEnabled: true,
              close: ignore,
              keyboard: ignore,
              cyclePointerMode: () => setState(() {
                mode = mode.next(supportsNativeTouch: supportsNativeTouch);
              }),
              display: ignore,
              rotate: ignore,
              more: ignore,
              help: ignore,
              macros: ignore,
            ),
          ),
        ),
      ));

      final touchButton = find.byTooltip('Touch mode');
      final position = tester.getCenter(touchButton);
      expect(find.byIcon(Icons.touch_app), findsOneWidget);
      await tester.tap(touchButton);
      await tester.pump();

      final mouseButton = find.byTooltip('Mouse mode');
      expect(tester.getCenter(mouseButton), position);
      expect(find.byIcon(Icons.mouse), findsOneWidget);
      await tester.tap(mouseButton);
      await tester.pump();

      final nativeButton = find.byTooltip('Windows native touch');
      if (supportsNativeTouch) {
        expect(tester.getCenter(nativeButton), position);
        expect(find.byIcon(Icons.back_hand_outlined), findsOneWidget);
        await tester.tap(nativeButton);
        await tester.pump();
      }
      expect(tester.getCenter(touchButton), position);
      expect(find.byIcon(Icons.touch_app), findsOneWidget);
      expect(nativeButton, findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
