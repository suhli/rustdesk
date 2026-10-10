import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../common.dart' hide Dialog;
import '../../models/model.dart';
import '../../models/platform_model.dart';
import 'keyboard_macro.dart';
import 'preferences.dart';

Future<void> showIosMacros(BuildContext context,
    {FFI? ffi, bool Function()? sessionActive}) async {
  final sessionId = ffi?.sessionId;
  final peer = ffi?.ffiModel.pi;
  final runner = ffi == null
      ? null
      : KeyboardMacroRunner(
          canSend: () =>
              sessionActive?.call() == true &&
              !ffi.closed &&
              identical(peer, ffi.ffiModel.pi) &&
              !ffi.ffiModel.waitForFirstImage.value &&
              ffi.inputModel.keyboardPerm &&
              ffi.inputModel.keyboardInputAllowed &&
              !ffi.inputModel.isViewOnly &&
              !ffi.inputModel.isViewCamera,
          send: (key) => bind.sessionInputKey(
              sessionId: sessionId!,
              name: key.keyName!,
              down: false,
              press: true,
              alt: key.alt,
              ctrl: key.ctrl,
              shift: key.shift,
              command: key.command));
  try {
    await showDialog<void>(
        context: context,
        builder: (_) =>
            Dialog.fullscreen(child: IosMacrosPage(runner: runner)));
  } finally {
    runner?.cancel();
  }
}

class IosMacrosPage extends StatefulWidget {
  final KeyboardMacroRunner? runner;
  const IosMacrosPage({super.key, this.runner});
  @override
  State<IosMacrosPage> createState() => _IosMacrosPageState();
}

class _IosMacrosPageState extends State<IosMacrosPage>
    with WidgetsBindingObserver {
  List<KeyboardMacro> _macros = [];
  String? _loadError;
  String? _runningName;
  String? _status;
  bool _saving = false;
  bool get _busy => _saving || _runningName != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    try {
      _macros = KeyboardMacro.decode(IosPreferences.read('keyboard-macros'));
    } catch (e) {
      _loadError = 'Could not read saved macros.';
      debugPrint('Could not read iOS macros: $e');
    }
  }

  @override
  void dispose() {
    widget.runner?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) widget.runner?.cancel();
  }

  Future<void> _save(List<KeyboardMacro> macros) async {
    setState(() => _saving = true);
    try {
      await IosPreferences.write(
          'keyboard-macros', KeyboardMacro.encode(macros));
      if (mounted) setState(() => _macros = macros);
    } catch (e) {
      debugPrint('Could not save iOS macros: $e');
      if (mounted) showToast(translate('Could not save macros.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _edit({int? index, KeyboardMacro? initial}) async {
    final macro = await showDialog<KeyboardMacro>(
        context: context,
        builder: (_) => Dialog.fullscreen(
            child: _MacroEditor(
                initial: index == null ? initial : _macros[index])));
    if (macro == null || !mounted) return;
    final macros = [..._macros];
    if (index == null) {
      macros.add(macro);
    } else {
      macros[index] = macro;
    }
    await _save(macros);
  }

  Future<void> _delete(int index) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(translate('Delete macro?')),
                content: Text(_macros[index].name),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(translate('Cancel'))),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(translate('Delete'))),
                ]));
    if (confirmed == true && mounted) {
      await _save([..._macros]..removeAt(index));
    }
  }

  Future<void> _run(KeyboardMacro macro) async {
    final runner = widget.runner;
    if (runner == null || _busy) return;
    setState(() {
      _runningName = macro.name;
      _status = null;
    });
    try {
      final result = await runner.run(macro);
      if (mounted) {
        setState(() => _status = switch (result) {
              MacroResult.completed => 'Macro sent',
              MacroResult.cancelled => 'Macro stopped',
              MacroResult.unavailable => 'Remote keyboard is unavailable.',
            });
      }
    } catch (e) {
      debugPrint('Could not send iOS macro: $e');
      if (mounted) setState(() => _status = 'Could not send macro.');
    } finally {
      if (mounted) setState(() => _runningName = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(translate('Custom macros')), actions: [
        IconButton(
            tooltip: translate('Add macro'),
            icon: const Icon(Icons.add),
            onPressed: _busy || _loadError != null ? null : () => _edit()),
      ]),
      body: _loadError != null
          ? Center(child: Text(translate(_loadError!)))
          : ListView(padding: const EdgeInsets.all(16), children: [
              Text(translate(
                  'Macros are saved on this device. Run them from a remote session.')),
              if (_saving) const LinearProgressIndicator(),
              if (_runningName != null) ...[
                const LinearProgressIndicator(),
                ListTile(
                    title: Text(_runningName!),
                    trailing: TextButton(
                        onPressed: widget.runner?.cancel,
                        child: Text(translate('Stop')))),
              ],
              if (_status != null)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(translate(_status!))),
              if (_macros.isEmpty)
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(translate('No macros yet'))),
              for (var i = 0; i < _macros.length; i++)
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_macros[i].name,
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              Text(_macros[i]
                                  .steps
                                  .map((step) =>
                                      '${step.shortcut.label} (${step.delayMs} ms)')
                                  .join(' → ')),
                              Wrap(children: [
                                if (widget.runner != null)
                                  TextButton.icon(
                                      onPressed:
                                          _busy ? null : () => _run(_macros[i]),
                                      icon: const Icon(Icons.play_arrow),
                                      label: Text(translate('Run macro'))),
                                TextButton.icon(
                                    onPressed:
                                        _busy ? null : () => _edit(index: i),
                                    icon: const Icon(Icons.edit),
                                    label: Text(translate('Edit macro'))),
                                TextButton.icon(
                                    onPressed: _busy ? null : () => _delete(i),
                                    icon: const Icon(Icons.delete_outline),
                                    label: Text(translate('Delete'))),
                              ]),
                            ]))),
              TextButton(
                  onPressed: _busy
                      ? null
                      : () => _edit(
                              initial: KeyboardMacro(
                                  translate('Windows sleep'), [
                            MacroStep('Win+X', 300),
                            MacroStep('U', 200),
                            MacroStep('S', 0)
                          ])),
                  child: Text(translate('Add Windows sleep example'))),
            ]));
}

class _MacroEditor extends StatefulWidget {
  final KeyboardMacro? initial;
  const _MacroEditor({this.initial});
  @override
  State<_MacroEditor> createState() => _MacroEditorState();
}

class _MacroEditorState extends State<_MacroEditor> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _steps = [...?widget.initial?.steps];
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _step([int? index]) async {
    final value = await showDialog<MacroStep>(
        context: context,
        builder: (_) =>
            _StepEditor(initial: index == null ? null : _steps[index]));
    if (value == null || !mounted) return;
    setState(() {
      if (index == null) {
        _steps.add(value);
      } else {
        _steps[index] = value;
      }
      _error = null;
    });
  }

  void _move(int from, int to) =>
      setState(() => _steps.insert(to, _steps.removeAt(from)));

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(translate('Edit macro')), actions: [
        TextButton(
            onPressed: () {
              try {
                Navigator.pop(context, KeyboardMacro(_name.text, _steps));
              } on FormatException {
                setState(
                    () => _error = 'Enter a name and add at least one step.');
              }
            },
            child: Text(translate('Save macro'))),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
            controller: _name,
            maxLength: 80,
            decoration: InputDecoration(labelText: translate('Name'))),
        Text(translate(
            'Each step presses and releases its keys, then waits for the configured delay.')),
        Text(translate(
            'Menu shortcuts depend on the remote language. Adjust the keys and delays as needed.')),
        if (_error != null)
          Text(translate(_error!),
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        for (var i = 0; i < _steps.length; i++)
          Card(
              child: Column(children: [
            ListTile(
                leading: Text('${i + 1}'),
                title: Text(_steps[i].shortcut.label),
                subtitle: Text(
                    '${translate('Delay after key (ms)')}: ${_steps[i].delayMs}'),
                onTap: () => _step(i)),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              IconButton(
                  tooltip: translate('Move step up'),
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: i == 0 ? null : () => _move(i, i - 1)),
              IconButton(
                  tooltip: translate('Move step down'),
                  icon: const Icon(Icons.arrow_downward),
                  onPressed:
                      i + 1 == _steps.length ? null : () => _move(i, i + 1)),
              IconButton(
                  tooltip: translate('Delete'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => setState(() => _steps.removeAt(i))),
            ]),
          ])),
        TextButton.icon(
            onPressed: () => _step(),
            icon: const Icon(Icons.add),
            label: Text(translate('Add step'))),
      ]));
}

class _StepEditor extends StatefulWidget {
  final MacroStep? initial;
  const _StepEditor({this.initial});
  @override
  State<_StepEditor> createState() => _StepEditorState();
}

class _StepEditorState extends State<_StepEditor> {
  final _form = GlobalKey<FormState>();
  late final _keys =
      TextEditingController(text: widget.initial?.shortcut.label ?? '');
  late final _delay =
      TextEditingController(text: '${widget.initial?.delayMs ?? 300}');
  @override
  void dispose() {
    _keys.dispose();
    _delay.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(translate('Macro step')),
          content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                  child: Form(
                      key: _form,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        TextFormField(
                            controller: _keys,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: InputDecoration(
                                labelText: translate('Key or shortcut'),
                                hintText: 'Win+X / Ctrl+Shift+Esc / U'),
                            validator: (value) {
                              try {
                                MacroShortcut.parse(value ?? '');
                                return null;
                              } on FormatException {
                                return translate(
                                    'Use one key, optionally with Ctrl, Alt, Shift or Win.');
                              }
                            }),
                        const SizedBox(height: 12),
                        Text(translate(
                            'Keys: A-Z, 0-9, F1-F12, Enter, Esc, Tab, Space, Backspace, Delete, Insert, Home, End, PageUp, PageDown, Up, Down, Left, Right.')),
                        TextFormField(
                            controller: _delay,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            decoration: InputDecoration(
                                labelText: translate('Delay after key (ms)')),
                            validator: (value) {
                              final delay = int.tryParse(value ?? '');
                              return delay == null || delay < 0 || delay > 60000
                                  ? translate(
                                      'Enter a delay from 0 to 60000 ms.')
                                  : null;
                            }),
                      ])))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(translate('Cancel'))),
            TextButton(
                onPressed: () {
                  if (_form.currentState!.validate()) {
                    Navigator.pop(
                        context, MacroStep(_keys.text, int.parse(_delay.text)));
                  }
                },
                child: Text(translate('OK'))),
          ]);
}
