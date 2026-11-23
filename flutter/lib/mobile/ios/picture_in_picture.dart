import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../common.dart';
import '../../models/model.dart';
import 'preferences.dart';
import 'tailnet.dart';

enum RemotePipQuality { automatic, economy, high }

bool get iosAutomaticPip => IosPreferences.read('pip-automatic') != 'N';
RemotePipQuality get iosPipQuality => RemotePipQuality.values.firstWhere(
    (quality) => quality.name == IosPreferences.read('pip-quality'),
    orElse: () => RemotePipQuality.automatic);

class IosRemotePictureInPicture {
  IosRemotePictureInPicture(this.ffi, this.sessionOwner);

  static const _channel = MethodChannel('rustdesk/remote-pip');
  static int _nextToken = 0;
  static IosRemotePictureInPicture? _owner;
  final _token = (++_nextToken).toString();
  final FFI ffi;
  final Object sessionOwner;

  bool available = false;
  bool _active = false;
  bool _live = true;
  bool _attached = false;
  bool _manualStart = false;
  int _display = -1;
  int? _backgroundRetries;
  final _interruption = Stopwatch();
  Stopwatch? _foregroundResume;

  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  Future<void> attach() async {
    if (_attached) return;
    _attached = true;
    _owner = this;
    _channel.setMethodCallHandler(_handleState);
    final supported = await _configure();
    if (!_attached || !supported) return;
    available = true;
    ffi.ffiModel.addListener(_displayChanged);
    ffi.imageModel.addListener(_onFrame);
    ffi.ffiModel.onRemoteTransportError = _onTransportError;
    if (iosAutomaticPip) {
      sessionRefreshVideo(ffi.sessionId, ffi.ffiModel.pi);
    }
  }

  Future<bool> _configure() async {
    _display = ffi.ffiModel.pi.currentDisplay;
    if (_display < 0) return false;
    return await _call<bool>('configure', {
          'display': _display,
          'automatic': iosAutomaticPip,
          'quality': iosPipQuality.name,
        }) ??
        false;
  }

  void _displayChanged() {
    if (_display != ffi.ffiModel.pi.currentDisplay) unawaited(_configure());
  }

  Future<T?> _call<T>(String method,
      [Map<String, Object> args = const {}]) async {
    try {
      return await _channel.invokeMethod<T>(method, {'owner': _token, ...args});
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      debugPrint('Remote PiP $method failed (${error.code})');
      return null;
    }
  }

  Future<void> _handleState(MethodCall call) async {
    final args = call.arguments;
    if (call.method != 'state' || args is! Map || args['owner'] != _token) {
      return;
    }
    final state = args['state'];
    if (state == 'active' || state == 'suspended' || state == 'paused') {
      _active = true;
      _manualStart = false;
    } else if (state == 'stopped' || state == 'restored' || state == 'failed') {
      _active = false;
      if (state == 'stopped' && args['background'] == true) {
        EmbeddedTailnet.instance.remotePictureInPictureClosed(sessionOwner);
      }
      if (state == 'failed' && _manualStart && _foreground) {
        showToast(translate('Picture in Picture is unavailable'));
      }
      _manualStart = false;
    }
  }

  Future<void> toggle() async {
    if (!_attached || !_foreground) return;
    _manualStart = !_active;
    if (await _call<bool>('toggle') != true) {
      _manualStart = false;
      if (_attached) showToast(translate('Picture in Picture is unavailable'));
    } else if (_attached && _manualStart) {
      sessionRefreshVideo(ffi.sessionId, ffi.ffiModel.pi);
    }
  }

  bool _onTransportError(bool suggestedRetry, String message) {
    if (_live) {
      _live = false;
      _interruption
        ..reset()
        ..start();
      unawaited(_call<void>('connection', {'live': false}));
    }
    final canRetry = suggestedRetry ||
        message == 'Timeout' ||
        message == 'Reset by the peer';
    if (_active && !_foreground && canRetry) _backgroundRetries ??= 0;
    final retries = _backgroundRetries;
    if (retries == null) return suggestedRetry;
    if (retries >= 2 || !canRetry) return false;
    _backgroundRetries = retries + 1;
    return true;
  }

  void _onFrame() {
    if (ffi.imageModel.image == null) return;
    final resume = _foregroundResume;
    if (resume != null) {
      _foregroundResume = null;
      debugPrint(
          'iOS remote video rendered ${resume.elapsedMilliseconds}ms after resume');
    }
    if (_live) return;
    _live = true;
    _backgroundRetries = null;
    _interruption.stop();
    debugPrint('Remote PiP received video again after '
        '${_interruption.elapsedMilliseconds}ms');
    unawaited(_call<void>('connection', {'live': true}));
  }

  void resumed() {
    if (_attached && available) _foregroundResume = Stopwatch()..start();
  }

  void dispose() {
    if (!_attached) return;
    _attached = false;
    ffi.ffiModel.removeListener(_displayChanged);
    ffi.imageModel.removeListener(_onFrame);
    if (_owner == this) {
      _owner = null;
      ffi.ffiModel.onRemoteTransportError = null;
      _channel.setMethodCallHandler(null);
    }
    unawaited(_call<void>('detach'));
  }
}
