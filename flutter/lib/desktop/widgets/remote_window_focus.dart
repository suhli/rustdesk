import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../../common.dart';
import '../../consts.dart';
import '../../mobile/widgets/mobile_video_quality.dart';
import '../../mobile/widgets/remote_window_focus.dart';
import '../../models/model.dart';
import '../../models/state_model.dart';
import '../../models/window_focus_geometry.dart';

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

class DesktopFocusTitlebarDrag {
  DesktopFocusTitlebarDrag({
    required this.ffi,
    required this.focus,
    VoidCallback? startLocalDrag,
    VoidCallback? endLocalDrag,
    void Function(PointerDownEvent)? replayPointerDown,
    bool Function()? isFullscreen,
  })  : _startLocalDrag = startLocalDrag ?? _defaultStartLocalDrag,
        _endLocalDrag = endLocalDrag ?? _defaultEndLocalDrag,
        _replayPointerDown = replayPointerDown ?? ffi.inputModel.onPointDownImage,
        _isFullscreen = isFullscreen ?? (() => stateGlobal.fullscreen.isTrue);

  static const double titlebarHeightPx = 40.0;
  static const double captionButtonsWidthPx = 144.0;
  static const double dragThresholdPx = 4.0;

  final FFI ffi;
  final RemoteWindowFocus focus;
  final VoidCallback _startLocalDrag;
  final VoidCallback _endLocalDrag;
  final void Function(PointerDownEvent) _replayPointerDown;
  final bool Function() _isFullscreen;

  PointerDownEvent? _pendingDown;
  bool _draggingLocalWindow = false;

  static void _defaultStartLocalDrag() {
    WindowController.fromWindowId(stateGlobal.windowId).startDragging();
  }

  static void _defaultEndLocalDrag() {
    if (isMacOS) {
      WindowController.fromWindowId(stateGlobal.windowId).setMovable(false);
    }
  }

  static bool isInTitlebarDragZone(
    Offset remotePoint,
    Rect windowRect, {
    double displayScale = 1.0,
  }) {
    if (windowRect.isEmpty) return false;
    final scale = displayScale >= 1.0 ? displayScale : 1.0;
    final titlebarHeight =
        math.min(titlebarHeightPx * scale, windowRect.height * 0.25);
    final buttonsWidth =
        math.min(captionButtonsWidthPx * scale, windowRect.width * 0.35);
    final relX = remotePoint.dx - windowRect.left;
    final relY = remotePoint.dy - windowRect.top;
    return relY >= 0 &&
        relY <= titlebarHeight &&
        relX >= 0 &&
        relX < windowRect.width - buttonsWidth;
  }

  bool handlePointer(PointerEvent event) {
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
    if (_isFullscreen()) return false;
    final chosen = focus.selected;
    final geometry = ffi.canvasModel.windowFocus;
    if (chosen == null || chosen.minimized || geometry == null) return false;
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
    final local = Offset(
      event.position.dx - CanvasModel.leftToEdge,
      event.position.dy - CanvasModel.topToEdge,
    );
    final remote = geometry.localToDesktop(local);
    if (remote == null) return false;
    final pi = ffi.ffiModel.pi;
    final displayScale = pi.scaleOfDisplay(pi.currentDisplay);
    if (!isInTitlebarDragZone(remote, chosen.rect,
        displayScale: displayScale)) {
      return false;
    }
    _pendingDown = event;
    return true;
  }

  bool _handleMove(PointerMoveEvent event) {
    if (_draggingLocalWindow) return true;
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
    if (_pendingDown != null && event.pointer == _pendingDown!.pointer) {
      _pendingDown = null;
      return true;
    }
    return false;
  }

  void reset() {
    _pendingDown = null;
    if (_draggingLocalWindow) {
      _draggingLocalWindow = false;
      _endLocalDrag();
    }
  }
}
