import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../common.dart';
import '../../models/platform_model.dart';
import '../../utils/http_service.dart' as http;
import 'orientation.dart';
import 'preferences.dart';

const tailnetEnabledKey = 'ios-tailnet-enabled';
const tailnetApiKey = 'ios-tailnet-api';
const tailnetIdKey = 'ios-tailnet-id';
const tailnetRelayKey = 'ios-tailnet-relay';
const tailnetFallbackKey = 'ios-tailnet-fallback';

bool validTailnetControlUrl(String value) {
  if (value.isEmpty) return true;
  final uri = Uri.tryParse(value);
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment;
}

bool sameHttpOrigin(Uri a, Uri b) =>
    (a.scheme == 'http' || a.scheme == 'https') &&
    a.host.isNotEmpty &&
    a.scheme == b.scheme &&
    a.host.toLowerCase() == b.host.toLowerCase() &&
    a.port == b.port;

class EmbeddedTailnet extends ChangeNotifier with WidgetsBindingObserver {
  static final instance = EmbeddedTailnet();
  bool get enabled => bind.mainGetOptionSync(key: tailnetEnabledKey) == 'Y';
  bool get apiEnabled => bind.mainGetOptionSync(key: tailnetApiKey) != 'N';
  String get controlUrl => IosPreferences.read('tailnet-control-url');
  bool routeEnabled(String key) => bind.mainGetOptionSync(key: key) == 'Y';
  bool routesApi(Uri url) =>
      enabled &&
      apiEnabled &&
      sameHttpOrigin(url,
          Uri.tryParse(bind.mainGetOptionSync(key: 'api-server')) ?? Uri());

  String state = 'Stopped', error = '', name = '', ips = '', apiStatus = '';
  String _authUrl = '';
  bool busy = false,
      _initialized = false,
      _manualStop = false,
      _foreground = true;
  Timer? _poll;

  Uri? get authorizationUri {
    final uri = Uri.tryParse(_authUrl);
    if (uri == null ||
        (uri.scheme != 'https' &&
            !(uri.scheme == 'http' &&
                Uri.tryParse(controlUrl)?.scheme == 'http')) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return uri;
  }

  Future<void> setControlUrl(String value) async {
    if (busy || value == controlUrl) return;
    if (!validTailnetControlUrl(value)) {
      error =
          'Enter an HTTP or HTTPS control server URL without credentials, query or fragment.';
      notifyListeners();
      return;
    }
    // The settings dialog confirms this identity reset before changing networks.
    await forget();
    if (error.isNotEmpty) return;
    await IosPreferences.write('tailnet-control-url', value);
    notifyListeners();
  }

  void initialize() {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    if (enabled && IosPreferences.autoConnect) {
      if (IosPreferences.authorized) {
        connect();
      } else {
        state = 'NeedsLogin';
      }
    }
  }

  String _server(String key, int port) {
    final raw = bind.mainGetOptionSync(key: key).trim();
    if (raw.isEmpty || raw.contains('://')) {
      throw StateError(
          'Configure an explicit TCP server in ID/Relay Server settings.');
    }
    final uri = Uri.tryParse('tcp://$raw');
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.path.isNotEmpty) {
      throw StateError('Invalid server address.');
    }
    return '${uri.host.contains(':') ? '[${uri.host}]' : uri.host}:${uri.hasPort ? uri.port : port}';
  }

  Future<void> connect() async {
    if (!enabled || busy) return;
    _manualStop = false;
    busy = true;
    error = '';
    _authUrl = '';
    state = 'Starting';
    notifyListeners();
    try {
      // Reconnect deliberately replaces the old forwarders after server edits.
      await iosChannel.invokeMethod('tailnetStop');
      final api =
          apiEnabled ? bind.mainGetOptionSync(key: 'api-server').trim() : '';
      if (apiEnabled && api.isEmpty) {
        throw StateError(
            'Configure an explicit API Server in ID/Relay Server settings.');
      }
      final config = jsonEncode({
        'controlUrl': controlUrl,
        'api': api,
        'id': routeEnabled(tailnetIdKey)
            ? _server('custom-rendezvous-server', 21116)
            : '',
        'relay':
            routeEnabled(tailnetRelayKey) ? _server('relay-server', 21117) : ''
      });
      await iosChannel.invokeMethod('tailnetStart', config);
      await refresh();
    } on StateError catch (e) {
      state = 'Failed';
      error = e.message.toString();
    } catch (_) {
      state = 'Failed';
      error =
          'Could not start Tailscale. Check server settings, device unlock and network access.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    _poll?.cancel();
    if (!enabled) return;
    try {
      final raw = await iosChannel.invokeMethod<String>('tailnetStatus');
      final status = jsonDecode(raw ?? '{}') as Map<String, dynamic>;
      final wasRunning = state == 'Running';
      state = status['state'] as String? ?? 'Failed';
      error = status['error'] as String? ?? '';
      _authUrl = status['authUrl'] as String? ?? '';
      name = status['name'] as String? ?? '';
      ips = (status['ips'] as List? ?? []).join(', ');
      if (state == 'Running') {
        await IosPreferences.write('tailnet-authorized', 'Y');
        if (!wasRunning) {
          gFFI.userModel.refreshCurrentUser();
          unawaited(testApi());
        }
      }
    } catch (_) {
      state = 'Failed';
      error = 'Could not read Tailscale status. Retry the connection.';
    }
    notifyListeners();
    if (_foreground && state != 'Stopped' && state != 'Failed') {
      _poll = Timer(Duration(seconds: state == 'Running' ? 30 : 5), refresh);
    }
  }

  Future<void> authorize() async {
    if (!enabled || busy) return;
    await refresh();
    if (state == 'Stopped' || state == 'Failed') await connect();
    if (state == 'Failed' || !enabled) return;
    busy = true;
    error = '';
    notifyListeners();
    try {
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (_authUrl.isEmpty && DateTime.now().isBefore(deadline)) {
        if (!_foreground) return;
        await refresh();
        if (state == 'Failed' ||
            state == 'Running' ||
            state == 'NeedsMachineAuth') {
          return;
        }
        if (_authUrl.isEmpty) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }
      if (!_foreground) return;
      if (_authUrl.isEmpty) {
        error =
            'No authorization link received. Check the control server address and network, then retry.';
        return;
      }
      final uri = authorizationUri;
      if (uri == null ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        error = 'Could not open Tailscale authorization in the browser.';
      }
    } catch (_) {
      error = 'Could not open Tailscale authorization in the browser.';
    } finally {
      if (error.isNotEmpty) _poll?.cancel();
      busy = false;
      notifyListeners();
    }
  }

  Future<void> disconnect({bool manual = true}) async {
    if (busy) return;
    busy = true;
    _poll?.cancel();
    _manualStop = manual;
    notifyListeners();
    try {
      await iosChannel.invokeMethod('tailnetStop');
      state = 'Stopped';
      error = '';
      _authUrl = '';
    } catch (_) {
      state = 'Failed';
      error = 'Could not stop Tailscale. Retry disconnecting.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> setEnabled(bool value) async {
    if (busy) return;
    if (!value) {
      await disconnect();
      if (state != 'Stopped') return;
    }
    await bind.mainSetOption(key: tailnetEnabledKey, value: value ? 'Y' : 'N');
    notifyListeners();
    if (value && IosPreferences.autoConnect) await connect();
  }

  Future<void> setRoute(String key, bool value) async {
    if (busy) return;
    await disconnect();
    if (state != 'Stopped') return;
    await bind.mainSetOption(key: key, value: value ? 'Y' : 'N');
    notifyListeners();
  }

  Future<void> setFallback(bool value) async {
    await bind.mainSetOption(
        key: tailnetFallbackKey, value: value ? 'alternate' : '');
    notifyListeners();
  }

  Future<void> forget() async {
    if (busy) return;
    busy = true;
    _poll?.cancel();
    notifyListeners();
    try {
      await iosChannel.invokeMethod('tailnetForget');
      await IosPreferences.write('tailnet-authorized', 'N');
      state = 'NeedsLogin';
      _authUrl = '';
      name = '';
      ips = '';
      error = '';
      _manualStop = true;
    } catch (_) {
      error =
          'Could not clear the local identity. Retry after unlocking the device.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> testApi() async {
    if (!enabled ||
        !apiEnabled ||
        state != 'Running' ||
        apiStatus == 'Checking...') {
      return;
    }
    apiStatus = 'Checking...';
    notifyListeners();
    try {
      final api = bind
          .mainGetOptionSync(key: 'api-server')
          .replaceFirst(RegExp(r'/+$'), '');
      final response = await http.get(Uri.parse('$api/api/login-options'));
      apiStatus =
          '${translate(response.statusCode < 500 ? 'API reachable' : 'API unavailable')} (HTTP ${response.statusCode})';
    } catch (_) {
      apiStatus = 'API unreachable. Check Tailscale, server address and ACLs.';
    } finally {
      notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!enabled) return;
    if (_foreground) {
      if (!_manualStop &&
          IosPreferences.autoConnect &&
          IosPreferences.authorized &&
          this.state == 'Stopped') {
        connect();
      } else {
        refresh();
      }
    } else if (state == AppLifecycleState.paused) {
      _poll?.cancel();
      if (!iosOrientation.inSession && this.state == 'Running') {
        disconnect(manual: false);
      }
    }
  }
}
