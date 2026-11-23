import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../consts.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';

const windowsNativeTouchOption = 'windows-native-touch';

class WindowsTouchInput {
  WindowsTouchInput(this.ffi);

  final FFI ffi;
  final _contacts = <int, Offset>{};
  Future<void> _pending = Future.value();
  Timer? _hold;

  bool get supported =>
      ffi.ffiModel.isPeerWindows &&
      ffi.ffiModel.pi.platformAdditions['native_touch'] == true;

  void update(PointerEvent event, String phase) {
    if (event.kind != PointerDeviceKind.touch) return;
    final id = event.pointer;
    final down = phase == 'down';
    if (down) {
      if (_contacts.length >= 10 || _contacts.containsKey(id)) return;
    } else if (!_contacts.containsKey(id)) {
      return;
    }
    if (!supported || ffi.ffiModel.viewOnly || !ffi.ffiModel.keyboard) {
      cancel();
      return;
    }
    final position =
        phase == 'cancel' ? null : _map(event.localPosition, clamp: !down);
    if (position != null && (down || _contacts[id] != position)) {
      _send(down ? 'down' : 'move', id, position);
      _contacts[id] = position;
      _hold ??= Timer.periodic(const Duration(milliseconds: 40), (_) {
        if (!supported || ffi.ffiModel.viewOnly || !ffi.ffiModel.keyboard) {
          cancel();
          return;
        }
        // Windows requires update frames even when a held finger is stationary.
        final contact = _contacts.entries.first;
        _send('move', contact.key, contact.value);
      });
    }
    if (phase == 'up' || phase == 'cancel') {
      final last = _contacts.remove(id);
      if (last != null) _send(phase, id, last);
      if (_contacts.isEmpty) _stopHold();
    }
  }

  Offset? _map(Offset local, {required bool clamp}) {
    final focus = ffi.canvasModel.windowFocus;
    if (focus != null) return focus.localToDesktop(local, clamp: clamp);
    final rect = ffi.ffiModel.rect;
    if (rect == null || rect.isEmpty) return null;
    final remote = ffi.inputModel.handlePointerDevicePos(kPointerEventKindTouch,
        local.dx, local.dy - ffi.canvasModel.getAdjustY(), false, 'move',
        onExit: clamp);
    if (remote == null || !remote.x.isFinite || !remote.y.isFinite) return null;
    final point = Offset(remote.x.toDouble(), remote.y.toDouble());
    if (!clamp && !rect.contains(point)) return null;
    return Offset(point.dx.clamp(rect.left, rect.right - 1).toDouble(),
        point.dy.clamp(rect.top, rect.bottom - 1).toDouble());
  }

  void cancel() {
    if (_contacts.isEmpty) return;
    _stopHold();
    _contacts.clear();
    _send('cancel-all', 0, Offset.zero);
  }

  void _stopHold() {
    _hold?.cancel();
    _hold = null;
  }

  void _send(String phase, int id, Offset position) {
    final message = jsonEncode({
      'k': 'native-touch',
      'v': {
        'phase': phase,
        'id': id,
        'x': position.dx.round(),
        'y': position.dy.round(),
      },
    });
    _pending = _pending.then((_) async {
      await bind.sessionSendPointer(sessionId: ffi.sessionId, msg: message);
    }).catchError((Object error) {
      debugPrint('Windows touch input could not be sent: $error');
    });
  }
}

class WindowsTouchRegion extends StatefulWidget {
  const WindowsTouchRegion(
      {super.key, required this.input, required this.child});

  final WindowsTouchInput input;
  final Widget child;

  @override
  State<WindowsTouchRegion> createState() => _WindowsTouchRegionState();
}

class _WindowsTouchRegionState extends State<WindowsTouchRegion> {
  @override
  Widget build(BuildContext context) {
    final input = widget.input;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) => input.update(event, 'down'),
      onPointerMove: (event) => input.update(event, 'move'),
      onPointerUp: (event) => input.update(event, 'up'),
      onPointerCancel: (event) => input.update(event, 'cancel'),
      child: widget.child,
    );
  }

  @override
  void dispose() {
    widget.input.cancel();
    super.dispose();
  }
}
