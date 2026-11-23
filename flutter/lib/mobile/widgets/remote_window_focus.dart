import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../common.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import '../../models/window_focus_geometry.dart';
import 'mobile_video_quality.dart';

const _fitOption = 'mobile-window-focus-fit';

class RemoteAppWindow {
  const RemoteAppWindow(this.id, this.title, this.app, this.rect);

  final String id, title, app;
  final Rect rect;

  static RemoteAppWindow? parse(Object? value) {
    if (value is! Map) return null;
    final id = value['id'], title = value['title'], app = value['app'];
    final x = value['x'], y = value['y'];
    final width = value['width'], height = value['height'];
    if (id is! String ||
        title is! String ||
        app is! String ||
        x is! int ||
        y is! int ||
        width is! int ||
        height is! int ||
        width <= 0 ||
        height <= 0) {
      return null;
    }
    return RemoteAppWindow(
        id,
        title,
        app,
        Rect.fromLTWH(
            x.toDouble(), y.toDouble(), width.toDouble(), height.toDouble()));
  }
}

class RemoteWindowFocus extends ChangeNotifier {
  RemoteWindowFocus(this.ffi, {required this.onCrop});

  final FFI ffi;
  final ValueChanged<Rect?> onCrop;
  List<RemoteAppWindow>? _windows;
  RemoteAppWindow? selected;
  WindowFocusFit fit = WindowFocusFit.contain;
  bool _picking = false;
  bool _disposed = false;
  Timer? _poll;
  Rect? _crop;

  bool get _peerSupportsWindowFocus =>
      ffi.ffiModel.pi.platformAdditions['remote_window_focus'] == true;

  bool get supported =>
      ffi.ffiModel.isPeerWindows &&
      ffi.ffiModel.keyboard &&
      _peerSupportsWindowFocus;

  Future<void> pick(BuildContext context) async {
    if (_disposed || _picking || !ffi.ffiModel.isPeerWindows) return;
    if (!supported) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(translate('Focus a remote window')),
          content: Text(translate(_peerSupportsWindowFocus
              ? 'window_focus_keyboard_permission_tip'
              : 'window_focus_peer_upgrade_tip')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(translate('OK')),
            ),
          ],
        ),
      );
      return;
    }
    fit = WindowFocusFit.values.firstWhere(
      (fit) => fit.name == bind.getLocalFlutterOption(k: _fitOption),
      orElse: () => WindowFocusFit.contain,
    );
    _picking = true;
    _windows = null;
    _updatePolling();
    final chosen = await showDialog<RemoteAppWindow>(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
          animation: this,
          builder: (_, __) {
            final windows = _windows;
            return AlertDialog(
              title: Text(translate('Focus a remote window')),
              content: SizedBox(
                  width: 420,
                  height: 290,
                  child: windows == null
                      ? const Center(child: CircularProgressIndicator())
                      : windows.isEmpty
                          ? Center(
                              child:
                                  Text(translate('No visible remote windows')))
                          : ListView.builder(
                              itemCount: windows.length,
                              itemBuilder: (_, index) {
                                final window = windows[index];
                                return ListTile(
                                  title: Text(window.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                  subtitle: window.app.isEmpty
                                      ? null
                                      : Text(window.app),
                                  selected: selected?.id == window.id,
                                  onTap: () =>
                                      Navigator.pop(dialogContext, window),
                                );
                              })),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text(translate('Cancel')))
              ],
            );
          }),
    );
    if (_disposed) return;
    _picking = false;
    if (chosen != null) _select(chosen);
    _updatePolling();
  }

  void _updatePolling() {
    if (_picking || selected != null) {
      if (_poll == null) {
        ffi.ffiModel.onRemoteWindows = _receive;
        ffi.ffiModel.addListener(_displayChanged);
        unawaited(_request());
        _poll = Timer.periodic(
            const Duration(seconds: 1), (_) => unawaited(_request()));
      }
    } else if (_poll != null) {
      _poll?.cancel();
      _poll = null;
      ffi.ffiModel.onRemoteWindows = null;
      ffi.ffiModel.removeListener(_displayChanged);
    }
  }

  Future<void> _request() async {
    if (!supported) {
      if (selected != null) clear();
      return;
    }
    try {
      await bind.sessionSendPointer(
          sessionId: ffi.sessionId, msg: '{"k":"remote-windows","v":{}}');
    } catch (error) {
      debugPrint('Remote window list request failed: $error');
    }
  }

  void _receive(String data) {
    try {
      final snapshot = jsonDecode(data);
      if (snapshot is! List) return;
      _windows = snapshot
          .map(RemoteAppWindow.parse)
          .whereType<RemoteAppWindow>()
          .toList();
    } on FormatException catch (error) {
      debugPrint('Invalid remote window list: ${error.message}');
      return;
    }
    final selection = selected;
    if (selection != null) {
      final windows = _windows!;
      for (final window in windows) {
        if (window.id != selection.id) continue;
        final pi = ffi.ffiModel.pi;
        final display = pi.getDisplayRect(pi.currentDisplay);
        if (window.rect != selection.rect ||
            display == null ||
            window.rect.intersect(display).isEmpty) {
          _select(window);
        }
        if (_picking) notifyListeners();
        return;
      }
      clear();
    } else if (_picking) {
      notifyListeners();
    }
  }

  void _select(RemoteAppWindow window) {
    final pi = ffi.ffiModel.pi;
    var index = -1;
    var largest = 0.0;
    for (var i = 0; i < pi.displays.length; i++) {
      final display = pi.getDisplayRect(i);
      if (display == null) continue;
      final area = window.rect.intersect(display);
      if (area.isEmpty) continue;
      final pixels = area.width * area.height;
      if (pixels > largest || (pixels == largest && i == pi.currentDisplay)) {
        index = i;
        largest = pixels;
      }
    }
    if (index < 0) {
      clear();
      return;
    }
    selected = window;
    if (index != pi.currentDisplay) {
      ffi.canvasModel.windowFocus = null;
      openMonitorInTheSameTab(index, ffi, pi,
          updateCursorPos: false, recordSelection: false);
    }
    _displayChanged();
    notifyListeners();
  }

  void _displayChanged() {
    final pi = ffi.ffiModel.pi;
    final rect = pi.getDisplayRect(pi.currentDisplay);
    final window = selected;
    Rect? crop;
    if (rect != null && window != null) {
      final clip = rect.intersect(window.rect);
      if (!clip.isEmpty) crop = clip.shift(-rect.topLeft);
    }
    if (_crop != crop) {
      _crop = crop;
      onCrop(crop);
    }
  }

  void setFit(WindowFocusFit value) {
    fit = value;
    unawaited(bind.setLocalFlutterOption(k: _fitOption, v: value.name));
    notifyListeners();
  }

  void clear() {
    selected = null;
    ffi.canvasModel.windowFocus = null;
    _displayChanged();
    _updatePolling();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _picking = false;
    selected = null;
    ffi.canvasModel.windowFocus = null;
    _updatePolling();
    super.dispose();
  }
}

class RemoteWindowFocusView extends StatelessWidget {
  const RemoteWindowFocusView(
      {super.key,
      required this.focus,
      required this.cursor,
      this.enhancement,
      required this.desktop});

  final RemoteWindowFocus focus;
  final bool cursor;
  final Widget desktop;
  final MobileVideoQuality? enhancement;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: Listenable.merge([focus, enhancement]),
      builder: (context, _) {
        final chosen = focus.selected;
        if (chosen == null) return desktop;
        final imageModel = context.watch<ImageModel>();
        final cursorModel = context.watch<CursorModel>();
        final ffiModel = context.watch<FfiModel>();
        final image = imageModel.image;
        final display = ffiModel.rect;
        return LayoutBuilder(builder: (_, bounds) {
          final geometry = display == null ||
                  image == null ||
                  imageModel.mobileImageDisplay != ffiModel.pi.currentDisplay
              ? null
              : WindowFocusGeometry.create(
                  chosen.rect, display, bounds.biggest, focus.fit);
          focus.ffi.canvasModel.windowFocus = geometry;
          if (geometry == null || image == null) return desktop;
          final cursorImage =
              cursor ? cursorModel.image ?? preDefaultCursor.image : null;
          final hotspot = cursorModel.image == null && cursorImage != null
              ? Offset(cursorImage.width / 2, cursorImage.height / 2)
              : Offset(cursorModel.hotx, cursorModel.hoty);
          final quality = enhancement;
          final frame = quality?.sample(image, geometry.source) ??
              (image: image, region: geometry.source);
          return SizedBox.expand(
              child: CustomPaint(
                  painter: _FocusPainter(
                      geometry,
                      frame,
                      quality?.filterQuality ?? FilterQuality.none,
                      cursorImage,
                      cursorModel.offset,
                      hotspot)));
        });
      });
}

class _FocusPainter extends CustomPainter {
  _FocusPainter(this.geometry, this.frame, this.filterQuality, this.cursor,
      this.position, this.hotspot);

  final WindowFocusGeometry geometry;
  final MobileVideoFrame frame;
  final FilterQuality filterQuality;
  final ui.Image? cursor;
  final Offset position, hotspot;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(geometry.viewport);
    canvas.drawImageRect(frame.image, frame.region, geometry.destination,
        Paint()..filterQuality = filterQuality);
    final shape = cursor;
    if (shape != null && geometry.desktopRect.contains(position)) {
      canvas.clipRect(geometry.destination);
      final origin = geometry.desktopToLocal(position - hotspot);
      canvas.drawImageRect(
          shape,
          Rect.fromLTWH(0, 0, shape.width.toDouble(), shape.height.toDouble()),
          Rect.fromLTWH(origin.dx, origin.dy, shape.width * geometry.scaleX,
              shape.height * geometry.scaleY),
          Paint());
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FocusPainter old) =>
      frame != old.frame ||
      filterQuality != old.filterQuality ||
      cursor != old.cursor ||
      position != old.position ||
      hotspot != old.hotspot ||
      geometry != old.geometry;
}
