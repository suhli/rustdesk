import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../../common.dart';
import '../../common/widgets/dialog.dart';
import '../../consts.dart';
import '../../mobile/widgets/mobile_video_quality.dart';
import '../../mobile/widgets/remote_window_focus.dart';
import '../../models/model.dart';
import '../../models/state_model.dart';
import '../../models/window_focus_geometry.dart';
import 'tabbar_widget.dart' show toggleMaximize;

const desktopVideoQualityOption = 'desktop-video-quality';
const desktopWindowFocusFitOption = 'desktop-window-focus-fit';
const desktopSuperResolutionMaxInputPixels = 1920 * 1080;

bool get desktopSupportsWindowFocusAndEnhancement =>
    !isWeb && (isWindows || isMacOS);

MobileVideoQuality? createDesktopVideoQuality() =>
    desktopSupportsWindowFocusAndEnhancement
        ? MobileVideoQuality(
            optionKey: desktopVideoQualityOption,
            inputPixelLimit: desktopSuperResolutionMaxInputPixels,
          )
        : null;

RemoteWindowFocus? createDesktopWindowFocus(FFI ffi) =>
    desktopSupportsWindowFocusAndEnhancement
        ? RemoteWindowFocus(
            ffi,
            onCrop: (_) {},
            fitOption: desktopWindowFocusFitOption,
          )
        : null;

FilterQuality desktopTextureFilterQuality({
  required bool isViewOriginal,
  MobileVideoQuality? enhancement,
}) {
  if (enhancement != null && enhancement.mode != MobileVideoQualityMode.off) {
    return FilterQuality.high;
  }
  return isViewOriginal ? FilterQuality.none : FilterQuality.low;
}

FilterQuality desktopWindowFocusFilterQuality({
  required WindowFocusGeometry geometry,
  MobileVideoQuality? enhancement,
}) {
  if (enhancement != null && enhancement.mode != MobileVideoQualityMode.off) {
    return FilterQuality.high;
  }
  final isOriginalScale = (geometry.scaleX - 1.0).abs() < 0.001 &&
      (geometry.scaleY - 1.0).abs() < 0.001;
  return isOriginalScale ? FilterQuality.none : FilterQuality.low;
}

Widget? buildDesktopEnhancedNonTexturePaint({
  required ui.Image? image,
  required Size size,
  required double offsetX,
  required double offsetY,
  required double scale,
  required MobileVideoQuality? enhancement,
}) {
  if (enhancement == null ||
      enhancement.mode == MobileVideoQualityMode.off ||
      image == null ||
      !scale.isFinite ||
      scale <= 0) {
    return null;
  }
  final region =
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
  final frame = enhancement.sample(image, region);
  final destination = Rect.fromLTWH(
    (offsetX / scale).truncateToDouble() * scale,
    (offsetY / scale).truncateToDouble() * scale,
    region.width * scale,
    region.height * scale,
  );
  return CustomPaint(
    size: size,
    painter: MobileEnhancedFramePainter(
      frame,
      destination,
      enhancement.filterQuality,
    ),
  );
}

({Rect clipRect, Rect textureRect}) computeDesktopFocusTextureLayout(
  WindowFocusGeometry geometry,
  Rect display,
) {
  final clipRect = geometry.destination.intersect(geometry.viewport);
  final textureRect = Rect.fromLTWH(
    geometry.destination.left -
        clipRect.left -
        geometry.source.left * geometry.scaleX,
    geometry.destination.top -
        clipRect.top -
        geometry.source.top * geometry.scaleY,
    display.width * geometry.scaleX,
    display.height * geometry.scaleY,
  );
  return (clipRect: clipRect, textureRect: textureRect);
}

class DesktopWindowFocusView extends StatelessWidget {
  const DesktopWindowFocusView({
    super.key,
    required this.focus,
    required this.useTextureRender,
    required this.enhancement,
    required this.wrapSurface,
    required this.fallback,
  });

  final RemoteWindowFocus focus;
  final bool useTextureRender;
  final MobileVideoQuality? enhancement;
  final Widget Function(Widget child) wrapSurface;
  final Widget Function() fallback;

  @override
  Widget build(BuildContext context) {
    final chosen = focus.selected;
    if (chosen == null || chosen.minimized) {
      focus.ffi.canvasModel.windowFocus = null;
      return fallback();
    }
    final ffiModel = context.watch<FfiModel>();
    final imageModel = context.watch<ImageModel>();
    final curDisplay = ffiModel.pi.currentDisplay;
    final display = ffiModel.rect;
    final validSingleDisplay = curDisplay != kAllDisplayValue &&
        curDisplay >= 0 &&
        curDisplay < ffiModel.pi.displays.length;
    if (!validSingleDisplay || display == null) {
      focus.ffi.canvasModel.windowFocus = null;
      return fallback();
    }
    return LayoutBuilder(builder: (_, bounds) {
      final image = imageModel.image;
      final frameReady = useTextureRender ||
          (image != null && imageModel.mobileImageDisplay == curDisplay);
      final geometry = !frameReady
          ? null
          : WindowFocusGeometry.create(
              chosen.rect, display, bounds.biggest, focus.fit);
      focus.ffi.canvasModel.windowFocus = geometry;
      if (geometry == null) {
        return fallback();
      }
      final filterQuality = desktopWindowFocusFilterQuality(
        geometry: geometry,
        enhancement: enhancement,
      );
      if (useTextureRender) {
        final layout = computeDesktopFocusTextureLayout(geometry, display);
        if (layout.clipRect.isEmpty) {
          return fallback();
        }
        final textureId = focus.ffi.textureModel.getTextureId(curDisplay);
        return wrapSurface(
          SizedBox.expand(
            child: Stack(
              children: [
                Positioned.fromRect(
                  rect: layout.clipRect,
                  child: ClipRect(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fromRect(
                          rect: layout.textureRect,
                          child: Obx(() => Texture(
                                textureId: textureId.value,
                                filterQuality: filterQuality,
                              )),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      final frame = enhancement?.sample(image!, geometry.source) ??
          (image: image!, region: geometry.source);
      return wrapSurface(
        SizedBox.expand(
          child: CustomPaint(
            painter: _DesktopFocusImagePainter(geometry, frame, filterQuality),
          ),
        ),
      );
    });
  }
}

class _DesktopFocusImagePainter extends CustomPainter {
  _DesktopFocusImagePainter(this.geometry, this.frame, this.filterQuality);

  final WindowFocusGeometry geometry;
  final MobileVideoFrame frame;
  final FilterQuality filterQuality;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(geometry.viewport);
    canvas.drawImageRect(
      frame.image,
      frame.region,
      geometry.destination,
      Paint()..filterQuality = filterQuality,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DesktopFocusImagePainter old) =>
      frame != old.frame ||
      filterQuality != old.filterQuality ||
      geometry != old.geometry;
}

class DesktopFocusedCursorPainter extends CustomPainter {
  DesktopFocusedCursorPainter({
    required this.geometry,
    required this.cursor,
    required this.position,
    required this.hotspot,
    required this.zoomCursor,
  });

  final WindowFocusGeometry geometry;
  final ui.Image? cursor;
  final Offset position;
  final Offset hotspot;
  final bool zoomCursor;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = cursor;
    if (shape == null || !geometry.desktopRect.contains(position)) return;
    final clip = geometry.destination.intersect(geometry.viewport);
    if (clip.isEmpty) return;
    final scaleX = zoomCursor ? geometry.scaleX : 1.0;
    final scaleY = zoomCursor ? geometry.scaleY : 1.0;
    final origin = geometry.desktopToLocal(position) -
        Offset(hotspot.dx * scaleX, hotspot.dy * scaleY);
    canvas.save();
    canvas.clipRect(clip);
    canvas.drawImageRect(
      shape,
      Rect.fromLTWH(0, 0, shape.width.toDouble(), shape.height.toDouble()),
      Rect.fromLTWH(
        origin.dx,
        origin.dy,
        shape.width * scaleX,
        shape.height * scaleY,
      ),
      Paint(),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(DesktopFocusedCursorPainter old) =>
      cursor != old.cursor ||
      position != old.position ||
      hotspot != old.hotspot ||
      zoomCursor != old.zoomCursor ||
      geometry != old.geometry;
}

enum DesktopTitlebarHit { none, drag, minimize, maximize, close }

class DesktopFocusTitlebarDrag {
  DesktopFocusTitlebarDrag({
    required this.ffi,
    required this.focus,
    required bool Function() isEnabled,
    VoidCallback? startLocalDrag,
    VoidCallback? endLocalDrag,
    VoidCallback? minimizeLocalWindow,
    VoidCallback? toggleLocalMaximize,
    VoidCallback? closeLocalWindow,
    void Function(PointerDownEvent)? replayPointerDown,
  })  : _isEnabled = isEnabled,
        _startLocalDrag = startLocalDrag ?? _defaultStartLocalDrag,
        _endLocalDrag = endLocalDrag ?? _defaultEndLocalDrag,
        _minimizeLocalWindow =
            minimizeLocalWindow ?? _defaultMinimizeLocalWindow,
        _toggleLocalMaximize =
            toggleLocalMaximize ?? _defaultToggleLocalMaximize,
        _closeLocalWindow =
            closeLocalWindow ?? (() => unawaited(_defaultCloseLocalWindow(ffi))),
        _replayPointerDown =
            replayPointerDown ?? ffi.inputModel.onPointDownImage;

  static const double titlebarHeightPx = 40.0;
  static const double captionButtonsWidthPx = 138.0;
  static const double dragThresholdPx = 4.0;

  final FFI ffi;
  final RemoteWindowFocus focus;
  final bool Function() _isEnabled;
  final VoidCallback _startLocalDrag;
  final VoidCallback _endLocalDrag;
  final VoidCallback _minimizeLocalWindow;
  final VoidCallback _toggleLocalMaximize;
  final VoidCallback _closeLocalWindow;
  final void Function(PointerDownEvent) _replayPointerDown;

  PointerDownEvent? _pendingDown;
  DesktopTitlebarHit _pendingCaptionButton = DesktopTitlebarHit.none;
  int? _pendingCaptionPointer;
  bool _draggingLocalWindow = false;

  static void _defaultStartLocalDrag() {
    WindowController.fromWindowId(stateGlobal.windowId).startDragging();
  }

  static void _defaultEndLocalDrag() {
    if (isMacOS) {
      WindowController.fromWindowId(stateGlobal.windowId).setMovable(false);
    }
  }

  static void _defaultMinimizeLocalWindow() {
    WindowController.fromWindowId(stateGlobal.windowId).minimize();
  }

  static void _defaultToggleLocalMaximize() {
    toggleMaximize(false).then((maximize) {
      stateGlobal.setMaximized(maximize);
    });
  }

  static Future<void> _defaultCloseLocalWindow(FFI ffi) async {
    if (await showConnEndAuditDialogCloseCanceled(ffi: ffi)) {
      return;
    }
    closeConnection(id: ffi.id);
  }

  static DesktopTitlebarHit hitTestTitlebar(
    Offset remotePoint,
    Rect windowRect, {
    double displayScale = 1.0,
  }) {
    if (windowRect.isEmpty) return DesktopTitlebarHit.none;
    final scale = displayScale >= 1.0 ? displayScale : 1.0;
    final titlebarHeight =
        math.min(titlebarHeightPx * scale, windowRect.height * 0.25);
    final buttonsWidth =
        math.min(captionButtonsWidthPx * scale, windowRect.width * 0.35);
    final relX = remotePoint.dx - windowRect.left;
    final relY = remotePoint.dy - windowRect.top;
    if (relY < 0 || relY > titlebarHeight || relX < 0 || relX > windowRect.width) {
      return DesktopTitlebarHit.none;
    }
    final buttonsStart = windowRect.width - buttonsWidth;
    if (relX < buttonsStart) {
      return DesktopTitlebarHit.drag;
    }
    final slotWidth = buttonsWidth / 3.0;
    final offsetInButtons = relX - buttonsStart;
    if (offsetInButtons < slotWidth) {
      return DesktopTitlebarHit.minimize;
    }
    if (offsetInButtons < slotWidth * 2.0) {
      return DesktopTitlebarHit.maximize;
    }
    return DesktopTitlebarHit.close;
  }

  DesktopTitlebarHit _hitTestEvent(PointerEvent event) {
    final chosen = focus.selected;
    final geometry = ffi.canvasModel.windowFocus;
    if (chosen == null || chosen.minimized || geometry == null) {
      return DesktopTitlebarHit.none;
    }
    final local = Offset(
      event.position.dx - CanvasModel.leftToEdge,
      event.position.dy - CanvasModel.topToEdge,
    );
    final remote = geometry.localToDesktop(local);
    if (remote == null) return DesktopTitlebarHit.none;
    final pi = ffi.ffiModel.pi;
    return hitTestTitlebar(
      remote,
      chosen.rect,
      displayScale: pi.scaleOfDisplay(pi.currentDisplay),
    );
  }

  bool handlePointer(PointerEvent event) {
    if (!_isEnabled()) {
      reset();
      return false;
    }
    if (event is PointerDownEvent) {
      return _handleDown(event);
    }
    if (event is PointerMoveEvent) {
      return _handleMove(event);
    }
    if (event is PointerUpEvent) {
      return _handleUp(event);
    }
    if (event is PointerCancelEvent) {
      return _handleCancel(event);
    }
    return false;
  }

  bool _handleDown(PointerDownEvent event) {
    reset();
    final input = ffi.inputModel;
    if (input.relativeMouseMode.value ||
        input.ctrl ||
        input.alt ||
        input.shift ||
        input.command) {
      return false;
    }
    if (event.kind != PointerDeviceKind.mouse ||
        event.buttons != kPrimaryMouseButton) {
      return false;
    }
    final hit = _hitTestEvent(event);
    if (hit == DesktopTitlebarHit.none) return false;
    if (hit == DesktopTitlebarHit.drag) {
      _pendingDown = event;
      return true;
    }
    _pendingCaptionButton = hit;
    _pendingCaptionPointer = event.pointer;
    return true;
  }

  bool _handleMove(PointerMoveEvent event) {
    if (_draggingLocalWindow) return true;
    if (_pendingCaptionButton != DesktopTitlebarHit.none &&
        event.pointer == _pendingCaptionPointer) {
      return true;
    }
    final pending = _pendingDown;
    if (pending == null || event.pointer != pending.pointer) return false;
    if ((event.position - pending.position).distance < dragThresholdPx) {
      return true;
    }
    _pendingDown = null;
    _draggingLocalWindow = true;
    _startLocalDrag();
    return true;
  }

  bool _handleUp(PointerUpEvent event) {
    if (_draggingLocalWindow) {
      _draggingLocalWindow = false;
      _endLocalDrag();
      return true;
    }
    if (_pendingCaptionButton != DesktopTitlebarHit.none &&
        event.pointer == _pendingCaptionPointer) {
      final action = _pendingCaptionButton;
      _pendingCaptionButton = DesktopTitlebarHit.none;
      _pendingCaptionPointer = null;
      if (_hitTestEvent(event) == action) {
        switch (action) {
          case DesktopTitlebarHit.minimize:
            _minimizeLocalWindow();
            break;
          case DesktopTitlebarHit.maximize:
            _toggleLocalMaximize();
            break;
          case DesktopTitlebarHit.close:
            _closeLocalWindow();
            break;
          case DesktopTitlebarHit.none:
          case DesktopTitlebarHit.drag:
            break;
        }
      }
      return true;
    }
    final pending = _pendingDown;
    if (pending == null || event.pointer != pending.pointer) return false;
    _pendingDown = null;
    _replayPointerDown(pending);
    return false;
  }

  bool _handleCancel(PointerCancelEvent event) {
    if (_draggingLocalWindow) {
      _draggingLocalWindow = false;
      _endLocalDrag();
      return true;
    }
    if (_pendingCaptionButton != DesktopTitlebarHit.none &&
        event.pointer == _pendingCaptionPointer) {
      _pendingCaptionButton = DesktopTitlebarHit.none;
      _pendingCaptionPointer = null;
      return true;
    }
    if (_pendingDown != null && event.pointer == _pendingDown!.pointer) {
      _pendingDown = null;
      return true;
    }
    return false;
  }

  void reset() {
    _pendingDown = null;
    _pendingCaptionButton = DesktopTitlebarHit.none;
    _pendingCaptionPointer = null;
    if (_draggingLocalWindow) {
      _draggingLocalWindow = false;
      _endLocalDrag();
    }
  }
}
