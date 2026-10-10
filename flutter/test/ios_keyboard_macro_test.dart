import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/mobile/ios/keyboard_macro.dart';

void main() {
  test('saved macros retain combinations and delays and reject invalid steps',
      () {
    final macro = KeyboardMacro('Sleep',
        [MacroStep('Win+x', 300), MacroStep('u', 200), MacroStep('s', 0)]);
    final saved = KeyboardMacro.encode([macro]);
    final restored = KeyboardMacro.decode(saved).single;
    expect(restored.name, 'Sleep');
    expect(restored.steps.map((s) => s.shortcut.label), ['Win+X', 'U', 'S']);
    expect(restored.steps.map((s) => s.delayMs), [300, 200, 0]);
    final combo = MacroShortcut.parse('ctrl+shift+esc');
    expect(combo.keyName, 'VK_ESCAPE');
    expect(combo.ctrl && combo.shift, isTrue);
    for (final invalid in ['', 'Win+', 'A+B', 'Ctrl+Ctrl+X', 'F13']) {
      expect(() => MacroShortcut.parse(invalid), throwsFormatException);
    }
    expect(() => MacroStep('X', -1), throwsFormatException);
    expect(() => MacroStep('X', 60001), throwsFormatException);
    expect(() => KeyboardMacro.decode('{"version":1,"macros":[{}]}'),
        throwsFormatException);
  });

  testWidgets('sleep macro sends Win+X, U, S in order after each delay',
      (tester) async {
    final sent = <MacroShortcut>[];
    final runner = KeyboardMacroRunner(
        canSend: () => true, send: (key) async => sent.add(key));
    final result = runner.run(KeyboardMacro('Sleep',
        [MacroStep('Win+X', 300), MacroStep('U', 200), MacroStep('S', 0)]));
    await tester.pump();
    expect(sent.single.keyName, 'VK_X');
    expect(sent.single.command, isTrue);
    await tester.pump(const Duration(milliseconds: 299));
    expect(sent.length, 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(sent.last.keyName, 'VK_U');
    expect(sent.last.command, isFalse);
    await tester.pump(const Duration(milliseconds: 200));
    expect(sent.map((key) => key.keyName), ['VK_X', 'VK_U', 'VK_S']);
    expect(await result, MacroResult.completed);
  });

  testWidgets('stop or lost keyboard access prevents the remaining keys',
      (tester) async {
    for (final stop in [true, false]) {
      var allowed = true;
      final sent = <String>[];
      final runner = KeyboardMacroRunner(
          canSend: () => allowed, send: (key) async => sent.add(key.keyName!));
      final result = runner.run(KeyboardMacro(
          'Two keys', [MacroStep('A', 60000), MacroStep('B', 0)]));
      await tester.pump();
      if (stop) {
        runner.cancel();
      } else {
        allowed = false;
      }
      await tester.pump(stop ? Duration.zero : const Duration(seconds: 60));
      expect(
          await result, stop ? MacroResult.cancelled : MacroResult.unavailable);
      expect(sent, ['VK_A']);
      expect(runner.running, isFalse);
    }
  });
}
