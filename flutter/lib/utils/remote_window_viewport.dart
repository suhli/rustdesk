import 'dart:math' as math;
import 'dart:ui';

/// How a locally cropped remote window should occupy the controller viewport.
///
/// This changes only presentation and coordinate translation. It never requests
/// a resolution change, resizes a remote window, or changes the encoded stream.
enum RemoteWindowFit { contain, cover, stretch }

/// Pure geometry for presenting a rectangular portion of a remote desktop.
///
/// All remote coordinates are in desktop pixels (and may be negative on a
/// multi-monitor desktop). [sourceRect] is in the decoded image's pixel space;
/// [destinationRect] is in the controller widget's logical pixel space.
///
/// Recreate this object when the selected remote window, captured display,
/// or local layout changes. This class does not enumerate or move any windows.
class RemoteWindowViewport {
  RemoteWindowViewport._({
    required this.desktopBounds,
    required this.windowBounds,
    required this.viewportSize,
    required this.fit,
    required this.sourceRect,
    required this.destinationRect,
  });

  final Rect desktopBounds;
  final Rect windowBounds;
  final Size viewportSize;
  final RemoteWindowFit fit;
  final Rect sourceRect;
  final Rect destinationRect;

  Rect get viewportRect => Offset.zero & viewportSize;

  /// Returns null if the window is not visible in the captured desktop, or if
  /// any dimension is invalid. A multi-monitor window is clipped to the
  /// captured region; this is deliberately only a controller-side crop.
  static RemoteWindowViewport? create({
    required Rect desktopBounds,
    required Rect windowBounds,
    required Size viewportSize,
    RemoteWindowFit fit = RemoteWindowFit.contain,
  }) {
    bool valid(Rect rect) =>
        rect.left.isFinite &&
        rect.top.isFinite &&
        rect.width.isFinite &&
        rect.height.isFinite &&
        rect.width > 0 &&
        rect.height > 0;

    if (!valid(desktopBounds) ||
        !valid(windowBounds) ||
        !viewportSize.width.isFinite ||
        !viewportSize.height.isFinite ||
        viewportSize.width <= 0 ||
        viewportSize.height <= 0) {
      return null;
    }

    final visible = desktopBounds.intersect(windowBounds);
    if (!valid(visible)) return null;

    final sourceRect = visible.shift(-desktopBounds.topLeft);
    final sourceWidth = sourceRect.width;
    final sourceHeight = sourceRect.height;
    final availableWidth = viewportSize.width;
    final availableHeight = viewportSize.height;

    late final double targetWidth;
    late final double targetHeight;
    if (fit == RemoteWindowFit.stretch) {
      targetWidth = availableWidth;
      targetHeight = availableHeight;
    } else {
      final ratioX = availableWidth / sourceWidth;
      final ratioY = availableHeight / sourceHeight;
      final scale = fit == RemoteWindowFit.contain
          ? math.min(ratioX, ratioY)
          : math.max(ratioX, ratioY);
      targetWidth = sourceWidth * scale;
      targetHeight = sourceHeight * scale;
    }

    final destinationRect = Rect.fromLTWH(
      (availableWidth - targetWidth) / 2,
      (availableHeight - targetHeight) / 2,
      targetWidth,
      targetHeight,
    );
    return RemoteWindowViewport._(
      desktopBounds: desktopBounds,
      windowBounds: windowBounds,
      viewportSize: viewportSize,
      fit: fit,
      sourceRect: sourceRect,
      destinationRect: destinationRect,
    );
  }

  /// Map a touch/cursor position in the controller widget to remote desktop
  /// coordinates. Do not send input when null (letterboxing / outside image).
  Offset? viewportToRemote(Offset localPosition) {
    if (!viewportRect.contains(localPosition) ||
        !destinationRect.contains(localPosition)) {
      return null;
    }
    final imageX = sourceRect.left +
        (localPosition.dx - destinationRect.left) *
            sourceRect.width /
            destinationRect.width;
    final imageY = sourceRect.top +
        (localPosition.dy - destinationRect.top) *
            sourceRect.height /
            destinationRect.height;
    return Offset(
      imageX + desktopBounds.left,
      imageY + desktopBounds.top,
    );
  }

  /// Map a remote desktop cursor to the controller viewport, or hide it if
  /// outside the cropped/visible region.
  Offset? remoteToViewport(Offset remotePosition) {
    final localImage = remotePosition - desktopBounds.topLeft;
    if (!sourceRect.contains(localImage)) return null;
    final local = Offset(
      destinationRect.left +
          (localImage.dx - sourceRect.left) *
              destinationRect.width /
              sourceRect.width,
      destinationRect.top +
          (localImage.dy - sourceRect.top) *
              destinationRect.height /
              sourceRect.height,
    );
    return viewportRect.contains(local) ? local : null;
  }
}
