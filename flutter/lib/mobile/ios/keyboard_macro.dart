import 'dart:async';
import 'dart:convert';

class MacroShortcut {
  final String key;
  final Set<String> modifiers;
  MacroShortcut._(this.key, Set<String> modifiers)
      : modifiers = Set.unmodifiable(modifiers);

  static const _specialKeys = {
    'ENTER': 'VK_RETURN',
    'ESC': 'VK_ESCAPE',
    'TAB': 'VK_TAB',
    'SPACE': 'VK_SPACE',
    'BACKSPACE': 'VK_BACK',
    'DELETE': 'VK_DELETE',
    'INSERT': 'VK_INSERT',
    'HOME': 'VK_HOME',
    'END': 'VK_END',
    'PAGEUP': 'VK_PRIOR',
    'PAGEDOWN': 'VK_NEXT',
    'UP': 'VK_UP',
    'DOWN': 'VK_DOWN',
    'LEFT': 'VK_LEFT',
    'RIGHT': 'VK_RIGHT',
    'PRINTSCREEN': 'VK_SNAPSHOT',
    'CAPSLOCK': 'VK_CAPITAL',
    'SCROLLLOCK': 'VK_SCROLL',
    'PAUSE': 'VK_PAUSE',
    'MENU': 'Apps',
    'WIN': 'Meta',
    'CTRL': 'VK_CONTROL',
    'ALT': 'VK_MENU',
    'SHIFT': 'VK_SHIFT',
    'MINUS': 'VK_MINUS',
    'EQUAL': 'VK_PLUS',
    'COMMA': 'VK_COMMA',
    'PERIOD': '.',
    'SLASH': 'VK_SLASH',
  };
  static String _normalize(String key) => switch (key.trim().toUpperCase()) {
        'CMD' || 'META' => 'WIN',
        'CONTROL' => 'CTRL',
        'ESCAPE' => 'ESC',
        'RETURN' => 'ENTER',
        final value => value,
      };

  factory MacroShortcut.parse(String text) {
    final parts = text.split('+').map(_normalize).toList();
    final modifiers = parts.take(parts.length - 1).toSet();
    if (modifiers.length != parts.length - 1 ||
        modifiers
            .any((key) => !['CTRL', 'ALT', 'SHIFT', 'WIN'].contains(key)) ||
        modifiers.contains(parts.last)) {
      throw const FormatException('Invalid macro shortcut');
    }
    final shortcut = MacroShortcut._(parts.last, modifiers);
    if (shortcut.keyName == null) {
      throw const FormatException('Invalid macro shortcut');
    }
    return shortcut;
  }

  String? get keyName => RegExp(r'^([A-Z0-9]|F[1-9]|F1[0-2])$').hasMatch(key)
      ? 'VK_$key'
      : _specialKeys[key];
  bool get ctrl => modifiers.contains('CTRL');
  bool get alt => modifiers.contains('ALT');
  bool get shift => modifiers.contains('SHIFT');
  bool get command => modifiers.contains('WIN');
  String get label => [
        if (ctrl) 'Ctrl',
        if (alt) 'Alt',
        if (shift) 'Shift',
        if (command) 'Win',
        key,
      ].join('+');
}

class MacroStep {
  final MacroShortcut shortcut;
  final int delayMs;
  MacroStep(String keys, this.delayMs) : shortcut = MacroShortcut.parse(keys) {
    if (delayMs < 0 || delayMs > 60000) {
      throw const FormatException('Invalid macro delay');
    }
  }
  Map<String, dynamic> toJson() => {'keys': shortcut.label, 'delayMs': delayMs};
}

class KeyboardMacro {
  final String name;
  final List<MacroStep> steps;
  KeyboardMacro(String name, List<MacroStep> steps)
      : name = name.trim(),
        steps = List.unmodifiable(steps) {
    if (this.name.isEmpty || this.name.length > 80 || steps.isEmpty) {
      throw const FormatException('Invalid macro');
    }
  }

  static List<KeyboardMacro> decode(String source) {
    if (source.isEmpty) return [];
    final data = jsonDecode(source);
    if (data is! Map || data['version'] != 1 || data['macros'] is! List) {
      throw const FormatException('Invalid saved macros');
    }
    return (data['macros'] as List).map((macro) {
      if (macro is! Map ||
          macro['name'] is! String ||
          macro['steps'] is! List) {
        throw const FormatException('Invalid saved macro');
      }
      return KeyboardMacro(
          macro['name'],
          (macro['steps'] as List).map((step) {
            if (step is! Map ||
                step['keys'] is! String ||
                step['delayMs'] is! int) {
              throw const FormatException('Invalid saved macro step');
            }
            return MacroStep(step['keys'], step['delayMs']);
          }).toList());
    }).toList();
  }

  static String encode(List<KeyboardMacro> macros) => jsonEncode({
        'version': 1,
        'macros': macros
            .map((macro) => {
                  'name': macro.name,
                  'steps': macro.steps.map((step) => step.toJson()).toList(),
                })
            .toList(),
      });
}

enum MacroResult { completed, cancelled, unavailable }

class KeyboardMacroRunner {
  final bool Function() canSend;
  final Future<void> Function(MacroShortcut) send;
  Completer<void>? _cancel;
  bool get running => _cancel != null;
  KeyboardMacroRunner({required this.canSend, required this.send});

  void cancel() {
    final cancel = _cancel;
    if (cancel != null && !cancel.isCompleted) cancel.complete();
  }

  Future<MacroResult> run(KeyboardMacro macro) async {
    if (running) throw StateError('A macro is already running');
    final cancel = _cancel = Completer<void>();
    try {
      for (final step in macro.steps) {
        if (cancel.isCompleted) return MacroResult.cancelled;
        if (!canSend()) return MacroResult.unavailable;
        await send(step.shortcut);
        if (step.delayMs > 0) {
          final elapsed = Completer<void>();
          final timer =
              Timer(Duration(milliseconds: step.delayMs), elapsed.complete);
          try {
            await Future.any([elapsed.future, cancel.future]);
          } finally {
            timer.cancel();
          }
        }
      }
      return cancel.isCompleted ? MacroResult.cancelled : MacroResult.completed;
    } finally {
      _cancel = null;
    }
  }
}
