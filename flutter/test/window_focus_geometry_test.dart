import 'dart:ui';

import 'package:flutter_hbb/models/window_focus_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const display = Rect.fromLTWH(-1600, -100, 1600, 900);
  const window = Rect.fromLTWH(-1400, 0, 800, 400);
  const size = Size(400, 400);

  test('contain ignores letterbox taps and maps back to desktop pixels', () {
    final geometry = WindowFocusGeometry.create(
        window, display, size, WindowFocusFit.contain)!;
    expect(geometry.source, const Rect.fromLTWH(200, 100, 800, 400));
    expect(geometry.localToDesktop(const Offset(100, 40)), isNull);
    expect(geometry.localToDesktop(const Offset(100, 150)),
        const Offset(-1200, 100));
  });

  test('cover maps only the window section visible on the phone', () {
    final geometry = WindowFocusGeometry.create(
        window, display, size, WindowFocusFit.cover)!;
    expect(geometry.localToDesktop(Offset.zero), const Offset(-1200, 0));
    expect(geometry.desktopToLocal(const Offset(-800, 200)),
        const Offset(400, 200));
  });

  test('stretch uses distinct axes and clips to the captured monitor', () {
    const crossing = Rect.fromLTWH(-600, 0, 800, 300);
    final geometry = WindowFocusGeometry.create(
        crossing, display, size, WindowFocusFit.stretch)!;
    expect(geometry.source, const Rect.fromLTWH(1000, 100, 600, 300));
    expect(geometry.localToDesktop(const Offset(200, 100)),
        const Offset(-300, 75));
    expect(geometry.localToDesktop(const Offset(440, 100), clamp: true),
        const Offset(-1, 75));
  });
}
