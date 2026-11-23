import 'dart:math' as math;
import 'dart:ui';

enum WindowFocusFit { contain, cover, stretch }

class WindowFocusGeometry {
  WindowFocusGeometry._(this.desktopRect, this.source, this.viewport,
      this.destination, this.scaleX, this.scaleY);

  static WindowFocusGeometry? create(
      Rect window, Rect display, Size size, WindowFocusFit fit) {
    final visible = window.intersect(display);
    if (visible.isEmpty || size.isEmpty || !size.isFinite) return null;
    double sx = size.width / visible.width;
    double sy = size.height / visible.height;
    if (fit != WindowFocusFit.stretch) {
      sx = sy =
          fit == WindowFocusFit.cover ? math.max(sx, sy) : math.min(sx, sy);
    }
    final viewport = Offset.zero & size;
    return WindowFocusGeometry._(
      visible,
      visible.shift(-display.topLeft),
      viewport,
      Rect.fromCenter(
          center: viewport.center,
          width: visible.width * sx,
          height: visible.height * sy),
      sx,
      sy,
    );
  }

  final Rect desktopRect;
  final Rect source;
  final Rect viewport;
  final Rect destination;
  final double scaleX;
  final double scaleY;

  Offset desktopToLocal(Offset point) =>
      destination.topLeft +
      Offset((point.dx - desktopRect.left) * scaleX,
          (point.dy - desktopRect.top) * scaleY);

  Offset? localToDesktop(Offset point, {bool clamp = false}) {
    final visible = destination.intersect(viewport);
    if (!clamp && !visible.contains(point)) return null;
    return boundDesktop(desktopRect.topLeft +
        Offset(
            (point.dx.clamp(visible.left, visible.right) - destination.left) /
                scaleX,
            (point.dy.clamp(visible.top, visible.bottom) - destination.top) /
                scaleY));
  }

  Offset boundDesktop(Offset point) => Offset(
      point.dx.clamp(desktopRect.left, desktopRect.right - 1).toDouble(),
      point.dy.clamp(desktopRect.top, desktopRect.bottom - 1).toDouble());

  Offset moveDesktopCursor(Offset point, Offset localDelta) =>
      localToDesktop(desktopToLocal(point) + localDelta, clamp: true) ?? point;
}
