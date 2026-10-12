import 'package:flutter/material.dart';
import '../../common.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import 'keyboard_macro.dart';
import 'preferences.dart';
import 'session_macro_menu.dart';

class IosSessionMacros {
  KeyboardMacroRunner? _runner;
  bool _menuOpen = false;

  void cancel() => _runner?.cancel();

  Future<void> show(BuildContext context,
      {required FFI ffi, required bool Function() sessionActive}) async {
    if (_menuOpen) return;
    final sessionId = ffi.sessionId;
    final peer = ffi.ffiModel.pi;
    final List<KeyboardMacro> macros;
    try {
      macros = KeyboardMacro.decode(IosPreferences.read('keyboard-macros'));
    } catch (e) {
      debugPrint('Could not read iOS macros: $e');
      showToast(translate('Could not read saved macros.'));
      return;
    }
    final KeyboardMacro? selected;
    _menuOpen = true;
    try {
      selected = await showIosSessionMacroMenu(context,
          macros: macros,
          translate: translate,
          onStop: _runner?.running == true ? cancel : null);
    } finally {
      _menuOpen = false;
    }
    if (selected == null || !sessionActive()) return;
    final runner = _runner = KeyboardMacroRunner(
        canSend: () =>
            sessionActive() &&
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed &&
            !ffi.closed &&
            identical(peer, ffi.ffiModel.pi) &&
            !ffi.ffiModel.waitForFirstImage.value &&
            ffi.inputModel.keyboardPerm &&
            ffi.inputModel.keyboardInputAllowed &&
            !ffi.inputModel.isViewOnly &&
            !ffi.inputModel.isViewCamera,
        send: (key) => bind.sessionInputKey(
            sessionId: sessionId,
            name: key.keyName!,
            down: false,
            press: true,
            alt: key.alt,
            ctrl: key.ctrl,
            shift: key.shift,
            command: key.command));
    try {
      final result = await runner.run(selected);
      if (sessionActive()) {
        showToast(translate(switch (result) {
          MacroResult.completed => 'Macro sent',
          MacroResult.cancelled => 'Macro stopped',
          MacroResult.unavailable => 'Remote keyboard is unavailable.',
        }));
      }
    } catch (e) {
      debugPrint('Could not send iOS macro: $e');
      if (sessionActive()) showToast(translate('Could not send macro.'));
    }
  }
}
