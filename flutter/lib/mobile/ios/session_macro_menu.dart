import 'package:flutter/material.dart';
import 'keyboard_macro.dart';

Future<KeyboardMacro?> showIosSessionMacroMenu(BuildContext context,
    {required List<KeyboardMacro> macros,
    required String Function(String) translate,
    VoidCallback? onStop}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = ModalBottomSheetRoute<KeyboardMacro>(
      capturedThemes:
          InheritedTheme.capture(from: context, to: navigator.context),
      isScrollControlled: true,
      useSafeArea: true,
      modalBarrierColor: Colors.transparent,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      clipBehavior: Clip.antiAlias,
      builder: (context) => ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.4),
          child: SafeArea(
              top: false,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  const SizedBox(width: 16),
                  Icon(Icons.playlist_play,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(translate('Custom macros'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium)),
                  IconButton(
                      tooltip: translate('Close'),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close)),
                ]),
                const Divider(height: 1),
                Flexible(
                    child: ListView(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        children: [
                      if (onStop != null)
                        ListTile(
                            leading: const Icon(Icons.stop),
                            title: Text(translate('Stop')),
                            onTap: () {
                              onStop();
                              Navigator.pop(context);
                            }),
                      if (macros.isEmpty)
                        Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(translate('No macros yet'))),
                      for (final macro in macros)
                        ListTile(
                            leading: Icon(Icons.play_arrow,
                                color: onStop == null
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).disabledColor),
                            title: Text(macro.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                                macro.steps
                                    .map((step) => step.shortcut.label)
                                    .join(' → '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            enabled: onStop == null,
                            onTap: () => Navigator.pop(context, macro)),
                    ])),
              ]))));
  final selected = await navigator.push(route);
  // Wait for the exit animation so the remote result is visible from the first key.
  await route.completed;
  return selected;
}
