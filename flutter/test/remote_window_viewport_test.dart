import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/utils/remote_window_viewport.dart';

void main() {
  const desktop = Rect.fromLTWH(-1920, 0, 3840, 1080);
  const selected = Rect.fromLTWH(100, 100, 800, 600);

  test('contain keeps aspect ratio and maps both directions', () {
    final viewport = RemoteWindowViewport.create(
      desktopBounds: desktop,
      windowBounds: selected,
      viewportSize: const Size(400, 500),
    )!;
    expect(viewport.sourceRect, const Rect.fromLTWH(2020, 100, 800, 600));
    expect(viewport.destinationRect, const Rect.fromLTWH(0, 100, 400, 300));
    expect(viewport.viewportToRemote(const Offset(200, 250)),
        const Offset(500, 400));
    expect(viewport.remoteToViewport(const Offset(500, 400)),
        const Offset(200, 250));
    expect(viewport.viewportToRemote(const Offset(200, 50)), isNull);
    expect(viewport.viewportToRemote(const Offset(200, 450)), isNull);
    expect(viewport.remoteToViewport(const Offset(-1000, 500)), isNull);
  });

  test('stretch uses entire viewport with independent x/y scale', () {
    final viewport = RemoteWindowViewport.create(
      desktopBounds: desktop,
      windowBounds: selected,
      viewportSize: const Size(320, 640),
      fit: RemoteWindowFit.stretch,
    )!;
    expect(viewport.destinationRect, const Rect.fromLTWH(0, 0, 320, 640));
    expect(viewport.viewportToRemote(const Offset(160, 320)),
        const Offset(500, 400));
  });

  test('cover can hide cropped portions but maps visible points', () {
    final viewport = RemoteWindowViewport.create(
      desktopBounds: desktop,
      windowBounds: selected,
      viewportSize: const Size(300, 600),
      fit: RemoteWindowFit.cover,
    )!;
    expect(viewport.destinationRect, const Rect.fromLTWH(-250, 0, 800, 600));
    expect(viewport.viewportToRemote(const Offset(150, 300)),
        const Offset(500, 400));
    expect(viewport.remoteToViewport(const Offset(100, 400)), isNull);
  });

  test('clips partially visible window to captured desktop', () {
    final viewport = RemoteWindowViewport.create(
      desktopBounds: const Rect.fromLTWH(0, 0, 1920, 1080),
      windowBounds: const Rect.fromLTWH(-100, 20, 300, 300),
      viewportSize: const Size(200, 300),
      fit: RemoteWindowFit.stretch,
    )!;
    expect(viewport.sourceRect, const Rect.fromLTWH(0, 20, 200, 300));
    expect(viewport.viewportToRemote(const Offset(100, 150)),
        const Offset(100, 170));
  });

  test('invalid dimensions and off-screen windows are rejected', () {
    expect(
      RemoteWindowViewport.create(
        desktopBounds: desktop,
        windowBounds: const Rect.fromLTWH(5000, 10, 200, 200),
        viewportSize: const Size(400, 400),
      ),
      isNull,
    );
    expect(
      RemoteWindowViewport.create(
        desktopBounds: desktop,
        windowBounds: selected,
        viewportSize: Size.zero,
      ),
      isNull,
    );
  });
}
