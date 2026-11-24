import 'dart:async';
import 'package:flutter/material.dart';
import '../../common.dart';
import '../widgets/remote_window_focus.dart';
import '../widgets/windows_touch.dart';

/// Floats over the existing canvas without changing input coordinates.
class IosSessionToolbar extends StatefulWidget {
  final VoidCallback close, keyboard, cyclePointerMode;
  final VoidCallback display, rotate, more, help, macros;
  final VoidCallback? pictureInPicture;
  final RemoteWindowFocus? windowFocus;
  final MobilePointerMode pointerMode;
  final bool keyboardEnabled;
  const IosSessionToolbar(
      {super.key,
      required this.close,
      required this.keyboard,
      required this.cyclePointerMode,
      required this.display,
      required this.rotate,
      required this.more,
      required this.help,
      required this.macros,
      this.pictureInPicture,
      this.windowFocus,
      required this.pointerMode,
      required this.keyboardEnabled});
  @override
  State<IosSessionToolbar> createState() => _IosSessionToolbarState();
}

class _IosSessionToolbarState extends State<IosSessionToolbar> {
  Timer? _timer;
  bool _visible = true;
  @override
  void initState() {
    super.initState();
    _arm();
  }

  void _arm() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Widget _button(IconData icon, String label, VoidCallback? action) =>
      IconButton(
          tooltip: translate(label),
          icon: Icon(icon),
          onPressed: action == null
              ? null
              : () {
                  _arm();
                  action();
                });
  @override
  Widget build(BuildContext context) => SafeArea(
        child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Material(
                elevation: 4,
                color: Theme.of(context).colorScheme.surface.withAlpha(240),
                borderRadius: BorderRadius.circular(24),
                child: _visible
                    ? SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          _button(Icons.close, 'Close', widget.close),
                          _button(Icons.keyboard, 'Keyboard',
                              widget.keyboardEnabled ? widget.keyboard : null),
                          _button(
                              widget.pointerMode.icon,
                              widget.pointerMode.label,
                              widget.keyboardEnabled
                                  ? widget.cyclePointerMode
                                  : null),
                          _button(
                              Icons.desktop_windows, 'Display', widget.display),
                          if (widget.windowFocus case final focus?)
                            RemoteWindowFocusButton(
                                focus: focus, onInteraction: _arm),
                          if (widget.pictureInPicture != null)
                            _button(Icons.picture_in_picture_alt,
                                'Picture in picture', widget.pictureInPicture),
                          _button(Icons.screen_rotation, 'Rotate screen',
                              widget.rotate),
                          _button(Icons.playlist_play, 'Custom macros',
                              widget.macros),
                          _button(Icons.more_horiz, 'More', widget.more),
                          _button(Icons.help_outline, 'Help', widget.help),
                          _button(Icons.fullscreen, 'Fullscreen',
                              () => setState(() => _visible = false)),
                        ]))
                    : _button(Icons.expand_more, 'Show toolbar', () {
                        setState(() => _visible = true);
                        _arm();
                      }),
              ),
            )),
      );
}
