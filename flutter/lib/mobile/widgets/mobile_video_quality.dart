import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../models/platform_model.dart';

enum MobileVideoQualityMode { off, standard, ai }

const _qualityOption = 'mobile-video-quality';
const mobileSuperResolutionShader = 'shaders/mobile_super_resolution.frag';
typedef MobileVideoFrame = ({ui.Image image, Rect region});

class MobileVideoQuality extends ChangeNotifier {
  MobileVideoQuality({
    String optionKey = _qualityOption,
    this.inputPixelLimit = maxInputPixels,
  })  : _optionKey = optionKey,
        mode = MobileVideoQualityMode.values.firstWhere(
            (mode) => mode.name == bind.getLocalFlutterOption(k: optionKey),
            orElse: () => MobileVideoQualityMode.off);

  static const maxInputPixels = 640 * 1024;
  final String _optionKey;
  final int inputPixelLimit;
  final _clock = Stopwatch()..start();
  MobileVideoQualityMode mode;
  Future<ui.FragmentProgram>? _program;
  MobileVideoFrame? _latest, _cachedInput;
  ui.Image? _cachedOutput;
  bool _foreground = true;
  bool _busy = false;
  bool _fallback = false;
  bool _disposed = false;
  int _generation = 0;
  int _lastStart = -1000;
  int _minIntervalMs = 85;
  int _lastLog = 0;
  int _processed = 0;
  int _presented = 0;
  bool _presentedCached = false;

  FilterQuality get filterQuality => mode == MobileVideoQualityMode.off
      ? FilterQuality.none
      : FilterQuality.high;

  void setMode(MobileVideoQualityMode value) {
    if (value == mode) return;
    mode = value;
    _fallback = false;
    _minIntervalMs = 85;
    _lastStart = -1000;
    _lastLog = _clock.elapsedMilliseconds;
    _processed = 0;
    _presented = 0;
    _clearCache();
    unawaited(bind.setLocalFlutterOption(k: _optionKey, v: value.name));
    notifyListeners();
  }

  void setForeground(bool foreground) {
    if (_foreground == foreground || _disposed) return;
    _foreground = foreground;
    if (!foreground) _clearCache();
    if (foreground && mode == MobileVideoQualityMode.ai) notifyListeners();
  }

  MobileVideoFrame sample(ui.Image image, Rect region) {
    final original = (image: image, region: region);
    if (mode != MobileVideoQualityMode.ai || !_foreground || _fallback) {
      return original;
    }
    if (region.isEmpty ||
        region.longestSide > 1920 ||
        region.width * region.height > inputPixelLimit) {
      return original;
    }
    _latest = original;
    final result = _cachedOutput;
    if (result != null && _cachedInput == original) {
      if (!_presentedCached) {
        _presented++;
        _presentedCached = true;
      }
      return (
        image: result,
        region: Offset.zero &
            Size(result.width.toDouble(), result.height.toDouble())
      );
    }
    final now = _clock.elapsedMilliseconds;
    if (!_busy && now - _lastStart >= _minIntervalMs) {
      _busy = true;
      _lastStart = now;
      unawaited(_render(original, _generation));
    }
    return original;
  }

  Future<void> _render(MobileVideoFrame input, int generation) async {
    final image = input.image.clone();
    ui.FragmentShader? shader;
    ui.Picture? picture;
    try {
      final program = await (_program ??=
          ui.FragmentProgram.fromAsset(mobileSuperResolutionShader));
      if (generation != _generation) return;
      final watch = Stopwatch()..start();
      final source = input.region;
      final width = 2 * source.width.round();
      final height = 2 * source.height.round();
      shader = program.fragmentShader()
        ..setFloat(0, image.width.toDouble())
        ..setFloat(1, image.height.toDouble())
        ..setFloat(2, source.left)
        ..setFloat(3, source.top)
        ..setFloat(4, source.width)
        ..setFloat(5, source.height)
        ..setImageSampler(0, image);
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawRect(
          Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          Paint()..shader = shader);
      picture = recorder.endRecording();
      final output = await picture.toImage(width, height);
      if (generation != _generation) {
        output.dispose();
        return;
      }
      final elapsed = watch.elapsedMilliseconds;
      _minIntervalMs = math.max(85, math.min(500, elapsed * 5));
      _processed++;
      if (elapsed > 100) {
        _fallback = true;
        output.dispose();
        _clearCache();
        debugPrint(
            'Mobile video AI fell back to GPU sampling after ${elapsed}ms');
      } else if (_latest == input) {
        _cachedOutput?.dispose();
        _cachedInput = input;
        _cachedOutput = output;
        _presentedCached = false;
        notifyListeners();
      } else {
        output.dispose();
      }
      _log(elapsed, width * height * 4);
    } catch (error) {
      if (generation == _generation) {
        _fallback = true;
        _program = null;
        debugPrint('Mobile video AI unavailable, using GPU sampling: $error');
      }
    } finally {
      picture?.dispose();
      shader?.dispose();
      image.dispose();
      _busy = false;
    }
  }

  void _log(int processingMs, int outputBytes) {
    final now = _clock.elapsedMilliseconds;
    final duration = now - _lastLog;
    if (duration < 5000) return;
    debugPrint('Mobile video AI ${processingMs}ms/attempt, '
        '${(_processed * 1000 / duration).toStringAsFixed(1)} processed fps, '
        '${(_presented * 1000 / duration).toStringAsFixed(1)} presented fps, '
        '$outputBytes output bytes');
    _lastLog = now;
    _processed = 0;
    _presented = 0;
  }

  void _clearCache() {
    _generation++;
    _latest = null;
    _cachedInput = null;
    _cachedOutput?.dispose();
    _cachedOutput = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _clearCache();
    super.dispose();
  }
}

class MobileEnhancedFramePainter extends CustomPainter {
  MobileEnhancedFramePainter(this.frame, this.destination, this.filterQuality);

  final MobileVideoFrame frame;
  final Rect destination;
  final FilterQuality filterQuality;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(frame.image, frame.region, destination,
        Paint()..filterQuality = filterQuality);
  }

  @override
  bool shouldRepaint(MobileEnhancedFramePainter old) =>
      frame != old.frame ||
      destination != old.destination ||
      filterQuality != old.filterQuality;
}
