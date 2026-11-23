import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'the bundled model doubles a selected region and applies a learned residual',
      () async {
    final program = await ui.FragmentProgram.fromAsset(
        'shaders/mobile_super_resolution.frag');
    final source = ui.PictureRecorder();
    ui.Canvas(source)
      ..drawColor(const ui.Color(0xFF000000), ui.BlendMode.src)
      ..drawRect(const ui.Rect.fromLTWH(0, 0, 2, 4),
          ui.Paint()..color = const ui.Color(0xFF0000FF))
      ..drawRect(const ui.Rect.fromLTWH(4, 0, 2, 4),
          ui.Paint()..color = const ui.Color(0xFFFFFFFF));
    final sourcePicture = source.endRecording();
    final input = await sourcePicture.toImage(6, 4);
    addTearDown(sourcePicture.dispose);
    addTearDown(input.dispose);

    final shader = program.fragmentShader()
      ..setFloat(0, 6)
      ..setFloat(1, 4)
      ..setFloat(2, 2)
      ..setFloat(3, 0)
      ..setFloat(4, 4)
      ..setFloat(5, 4)
      ..setImageSampler(0, input);
    addTearDown(shader.dispose);
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
        const ui.Rect.fromLTWH(0, 0, 8, 8), ui.Paint()..shader = shader);
    final picture = recorder.endRecording();
    addTearDown(picture.dispose);
    final image = await picture.toImage(8, 8);
    addTearDown(image.dispose);
    final pixels = (await image.toByteData())!;
    int channel(int x, int c) => pixels.getUint8((4 * 8 + x) * 4 + c);
    expect(image.width, 2 * 4);
    expect(image.height, 2 * 4);
    expect(channel(0, 0), channel(0, 2));
    expect(channel(3, 0), lessThan(channel(4, 0)));
    expect([channel(3, 0), channel(4, 0)], isNot([64, 191]));
  });
}
