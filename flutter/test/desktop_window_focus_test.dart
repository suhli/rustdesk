import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/widgets/remote_window_focus.dart';
import 'package:flutter_hbb/generated_bridge.dart' show RustdeskImpl;
import 'package:flutter_hbb/mobile/widgets/mobile_video_quality.dart';
import 'package:flutter_hbb/mobile/widgets/remote_window_focus.dart';
import 'package:flutter_hbb/models/desktop_render_texture.dart';
import 'package:flutter_hbb/models/input_model.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/models/window_focus_geometry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

class _Binding extends Fake implements RustdeskImpl {
  final options = <String, String>{};

  @override
  String translate(
          {required String name, required String locale, dynamic hint}) =>
      name;

  @override
  String getLocalFlutterOption({required String k, dynamic hint}) =>
      options[k] ?? '';

  @override
  Future<void> setLocalFlutterOption(
      {required String k, required String v, dynamic hint}) async {
    options[k] = v;
  }

  @override
  Future<void> sessionSendPointer(
      {required UuidValue sessionId, required String msg, dynamic hint}) async {}
}

class _Peer extends Fake with ChangeNotifier implements FfiModel {
  _Peer() {
    pi.platformAdditions['remote_window_focus'] = true;
    pi.displays.add(Display()
      ..x = 0
      ..y = 0
      ..width = 1920
      ..height = 1080);
    pi.currentDisplay = 0;
  }

  @override
  final pi = PeerInfo();

  @override
  bool get keyboard => true;

  @override
  bool get isPeerWindows => true;

  @override
  Rect? get rect => pi.getDisplayRect(pi.currentDisplay);

  @override
  ValueChanged<String>? onRemoteWindows;
}

class _Image extends Fake with ChangeNotifier implements ImageModel {
  @override
  ui.Image? get image => null;

  @override
  int? mobileImageDisplay;
}

class _Canvas extends Fake implements CanvasModel {
  @override
  WindowFocusGeometry? windowFocus;
}

class _Texture extends Fake implements TextureModel {
  final id = 42.obs;

  @override
  RxInt getTextureId(int display) => id;
}

class _Input extends Fake implements InputModel {
  @override
  final relativeMouseMode = false.obs;
  @override
  bool ctrl = false;
  @override
  bool alt = false;
  @override
  bool shift = false;
  @override
  bool command = false;
}

class _Session extends Fake implements FFI {
  _Session(this.ffiModel);

  @override
  final FfiModel ffiModel;
  @override
  final CanvasModel canvasModel = _Canvas();
  @override
  final InputModel inputModel = _Input();
  @override
  final TextureModel textureModel = _Texture();
  @override
  final UuidValue sessionId = const Uuid().v4obj();
}

void main() {
  late _Binding binding;
  setUp(() {
    binding = _Binding();
    platformFFI.setBindingForTesting(binding);
  });

  test('desktop video quality defaults to off and upgrades sampling when set',
      () async {
    final quality = MobileVideoQuality(
      optionKey: desktopVideoQualityOption,
      inputPixelLimit: desktopSuperResolutionMaxInputPixels,
    );
    addTearDown(quality.dispose);

    expect(quality.mode, MobileVideoQualityMode.off);
    expect(
      desktopTextureFilterQuality(isViewOriginal: true, enhancement: quality),
      FilterQuality.none,
    );
    expect(
      desktopTextureFilterQuality(isViewOriginal: false, enhancement: quality),
      FilterQuality.low,
    );

    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const Color(0xFF112233), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(16, 16);
    addTearDown(picture.dispose);
    addTearDown(image.dispose);

    expect(
      buildDesktopEnhancedNonTexturePaint(
        image: image,
        size: const Size(32, 32),
        offsetX: 0,
        offsetY: 0,
        scale: 2,
        enhancement: quality,
      ),
      isNull,
    );

    quality.setMode(MobileVideoQualityMode.standard);
    expect(binding.options[desktopVideoQualityOption], 'standard');
    expect(
      desktopTextureFilterQuality(isViewOriginal: true, enhancement: quality),
      FilterQuality.high,
    );
    expect(
      buildDesktopEnhancedNonTexturePaint(
        image: image,
        size: const Size(32, 32),
        offsetX: 0,
        offsetY: 0,
        scale: 2,
        enhancement: quality,
      ),
      isA<CustomPaint>(),
    );

    quality.setMode(MobileVideoQualityMode.ai);
    expect(binding.options[desktopVideoQualityOption], 'ai');
    expect(
      desktopTextureFilterQuality(isViewOriginal: false, enhancement: quality),
      FilterQuality.high,
    );
  });

  test('computeDesktopFocusTextureLayout aligns source window to destination',
      () {
    const display = Rect.fromLTWH(0, 0, 1920, 1080);
    const window = Rect.fromLTWH(200, 100, 800, 600);
    const viewport = Size(1200, 600);

    for (final fit in WindowFocusFit.values) {
      final geometry =
          WindowFocusGeometry.create(window, display, viewport, fit)!;
      final layout = computeDesktopFocusTextureLayout(geometry, display);

      final mappedTopLeft = Offset(
        layout.clipRect.left +
            layout.textureRect.left +
            geometry.source.left * geometry.scaleX,
        layout.clipRect.top +
            layout.textureRect.top +
            geometry.source.top * geometry.scaleY,
      );
      final mappedBottomRight = Offset(
        layout.clipRect.left +
            layout.textureRect.left +
            geometry.source.right * geometry.scaleX,
        layout.clipRect.top +
            layout.textureRect.top +
            geometry.source.bottom * geometry.scaleY,
      );

      expect(mappedTopLeft.dx, closeTo(geometry.destination.left, 1e-6));
      expect(mappedTopLeft.dy, closeTo(geometry.destination.top, 1e-6));
      expect(mappedBottomRight.dx, closeTo(geometry.destination.right, 1e-6));
      expect(mappedBottomRight.dy, closeTo(geometry.destination.bottom, 1e-6));
    }
  });

  testWidgets('DesktopWindowFocusView crops texture and restores fallback',
      (tester) async {
    final peer = _Peer();
    final image = _Image();
    final session = _Session(peer);
    final focus = RemoteWindowFocus(
      session,
      onCrop: (_) {},
      fitOption: desktopWindowFocusFitOption,
    );
    final quality = MobileVideoQuality(
      optionKey: desktopVideoQualityOption,
      inputPixelLimit: desktopSuperResolutionMaxInputPixels,
    );
    addTearDown(focus.dispose);
    addTearDown(quality.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<FfiModel>.value(value: peer),
          ChangeNotifierProvider<ImageModel>.value(value: image),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: AnimatedBuilder(
                animation: Listenable.merge([focus, quality]),
                builder: (_, __) => DesktopWindowFocusView(
                  focus: focus,
                  useTextureRender: true,
                  enhancement: quality,
                  wrapSurface: (child) => child,
                  fallback: () => const Text('desktop-fallback'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('desktop-fallback'), findsOneWidget);
    expect(session.canvasModel.windowFocus, isNull);

    final pickFuture = focus.pick(tester.element(find.byType(Scaffold)));
    await tester.pump();
    peer.onRemoteWindows!.call(jsonEncode([
      {
        'id': '1:2',
        'title': 'Editor',
        'app': 'code.exe',
        'minimized': false,
        'x': 100,
        'y': 50,
        'width': 400,
        'height': 300,
      }
    ]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editor'));
    await tester.pumpAndSettle();
    await pickFuture;

    expect(find.text('desktop-fallback'), findsNothing);
    final texture = tester.widget<Texture>(find.byType(Texture));
    expect(texture.textureId, 42);
    expect(texture.filterQuality, FilterQuality.low);
    expect(session.canvasModel.windowFocus?.desktopRect,
        const Rect.fromLTWH(100, 50, 400, 300));

    quality.setMode(MobileVideoQualityMode.ai);
    await tester.pump();
    expect(
      tester.widget<Texture>(find.byType(Texture)).filterQuality,
      FilterQuality.high,
    );

    focus.clear();
    await tester.pump();
    expect(find.text('desktop-fallback'), findsOneWidget);
    expect(session.canvasModel.windowFocus, isNull);
  });

  test('window focus hides and restores desktop tab bar height independently',
      () {
    final state = stateGlobal;
    addTearDown(() {
      state.setWindowFocusHideTabBar(false);
      state.setFullscreen(false, procWnd: false);
    });
    expect(state.showTabBar.value, isTrue);
    expect(state.tabBarHeight, kDesktopRemoteTabBarHeight);

    state.setWindowFocusHideTabBar(true);
    expect(state.showTabBar.value, isFalse);
    expect(state.tabBarHeight, 0);

    state.setFullscreen(true, procWnd: false);
    expect(state.showTabBar.value, isFalse);
    expect(state.tabBarHeight, 0);

    state.setFullscreen(false, procWnd: false);
    expect(state.showTabBar.value, isFalse);
    expect(state.tabBarHeight, 0);

    state.setWindowFocusHideTabBar(false);
    expect(state.showTabBar.value, isTrue);
    expect(state.tabBarHeight, kDesktopRemoteTabBarHeight);
  });

  test(
      'collapsed focus hooks titlebar drag and min/max/close; expanded unhooks',
      () {
    final peer = _Peer();
    final session = _Session(peer);
    final focus = RemoteWindowFocus(session, onCrop: (_) {});
    addTearDown(focus.dispose);

    const windowRect = Rect.fromLTWH(100, 50, 800, 600);
    focus.selected =
        const RemoteAppWindow('1:2', 'Editor', 'code.exe', windowRect);
    session.canvasModel.windowFocus = WindowFocusGeometry.create(
      windowRect,
      const Rect.fromLTWH(0, 0, 1920, 1080),
      const Size(800, 600),
      WindowFocusFit.contain,
    );

    var toolbarCollapsed = true;
    var dragStarts = 0;
    var dragEnds = 0;
    var minimizes = 0;
    var maximizes = 0;
    var closes = 0;
    final replayedDowns = <PointerDownEvent>[];
    final interceptor = DesktopFocusTitlebarDrag(
      ffi: session,
      focus: focus,
      isEnabled: () => toolbarCollapsed,
      startLocalDrag: () => dragStarts++,
      endLocalDrag: () => dragEnds++,
      minimizeLocalWindow: () => minimizes++,
      toggleLocalMaximize: () => maximizes++,
      closeLocalWindow: () => closes++,
      replayPointerDown: replayedDowns.add,
    );

    final edge = Offset(CanvasModel.leftToEdge, CanvasModel.topToEdge);

    // 1. Drag in remote titlebar -> starts local drag, swallows down/move/cancel.
    final dragDown = PointerDownEvent(
      pointer: 1,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
      position: edge + const Offset(200, 20),
    );
    expect(interceptor.handlePointer(dragDown), isTrue);
    expect(dragStarts, 0);
    expect(
      interceptor.handlePointer(PointerMoveEvent(
        pointer: 1,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
        position: edge + const Offset(210, 20),
      )),
      isTrue,
    );
    expect(dragStarts, 1);
    expect(replayedDowns, isEmpty);
    expect(
      interceptor.handlePointer(PointerCancelEvent(
        pointer: 1,
        kind: PointerDeviceKind.mouse,
        position: edge + const Offset(210, 20),
      )),
      isTrue,
    );
    expect(dragEnds, 1);

    // 2. Click in remote titlebar (no drag) -> replays down and passes up.
    final clickDown = PointerDownEvent(
      pointer: 2,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
      position: edge + const Offset(200, 20),
    );
    expect(interceptor.handlePointer(clickDown), isTrue);
    expect(
      interceptor.handlePointer(PointerUpEvent(
        pointer: 2,
        kind: PointerDeviceKind.mouse,
        position: edge + const Offset(201, 20),
      )),
      isFalse,
    );
    expect(replayedDowns, [clickDown]);
    expect(dragStarts, 1);

    // 3. Top-right remote caption buttons map to local minimize / maximize / close.
    // buttonsStart = 800 - 138 = 662; slots: [662, 708), [708, 754), [754, 800].
    for (final (pointer, x) in [(3, 680.0), (4, 730.0), (5, 780.0)]) {
      expect(
        interceptor.handlePointer(PointerDownEvent(
          pointer: pointer,
          kind: PointerDeviceKind.mouse,
          buttons: kPrimaryMouseButton,
          position: edge + Offset(x, 20),
        )),
        isTrue,
      );
      expect(
        interceptor.handlePointer(PointerUpEvent(
          pointer: pointer,
          kind: PointerDeviceKind.mouse,
          position: edge + Offset(x, 20),
        )),
        isTrue,
      );
    }
    expect(minimizes, 1);
    expect(maximizes, 1);
    expect(closes, 1);

    // 4. Dragging off a caption button before release cancels cleanly.
    expect(
      interceptor.handlePointer(PointerDownEvent(
        pointer: 6,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
        position: edge + const Offset(780, 20),
      )),
      isTrue,
    );
    expect(
      interceptor.handlePointer(PointerUpEvent(
        pointer: 6,
        kind: PointerDeviceKind.mouse,
        position: edge + const Offset(400, 200),
      )),
      isTrue,
    );
    expect(closes, 1);

    // 5. Client area below titlebar passes through unhooked.
    expect(
      interceptor.handlePointer(PointerDownEvent(
        pointer: 7,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
        position: edge + const Offset(200, 200),
      )),
      isFalse,
    );

    // 6. Expanding toolbar unhooks both titlebar drag and caption buttons.
    toolbarCollapsed = false;
    expect(
      interceptor.handlePointer(PointerDownEvent(
        pointer: 8,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
        position: edge + const Offset(200, 20),
      )),
      isFalse,
    );
    expect(
      interceptor.handlePointer(PointerDownEvent(
        pointer: 9,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
        position: edge + const Offset(780, 20),
      )),
      isFalse,
    );
    expect(closes, 1);
  });
}
