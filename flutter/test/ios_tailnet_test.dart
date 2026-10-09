import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/mobile/ios/orientation.dart';
import 'package:flutter_hbb/mobile/ios/tailnet.dart';

class _EnabledTailnet extends EmbeddedTailnet {
  @override
  bool get enabled => true;
  @override
  String get controlUrl => 'http://headscale.example.test';
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const launcher = MethodChannel('plugins.flutter.io/url_launcher');
  late EmbeddedTailnet tailnet;

  setUp(() => tailnet = _EnabledTailnet());
  tearDown(() async {
    await tailnet.disconnect();
    tailnet.dispose();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(iosChannel, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(launcher, null);
  });

  test('home status distinguishes connection and authorization states', () {
    for (final entry in {
      'Starting': 'Connecting...',
      'NoState': 'Connecting...',
      'Running': 'Connected',
      'NeedsLogin': 'Authorization required',
      'NeedsMachineAuth': 'Approve this device on your control server',
      'Failed': 'Connection failed',
      'Stopped': 'Not connected',
    }.entries) {
      tailnet.state = entry.key;
      expect(tailnet.statusLabel, entry.value);
    }
  });

  test('authorization opens a Headscale link that arrives after the click',
      () async {
    var reads = 0;
    String? opened;
    const link = 'http://headscale.example.test/register/test-node';
    binding.defaultBinaryMessenger.setMockMethodCallHandler(iosChannel,
        (call) async {
      if (call.method != 'tailnetStatus') return null;
      return jsonEncode(
          {'state': 'NeedsLogin', 'authUrl': ++reads < 3 ? '' : link});
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(launcher,
        (call) async {
      opened = (call.arguments as Map)['url'] as String;
      return true;
    });
    await tailnet.authorize();
    expect(opened, link);
    expect(tailnet.error, isEmpty);
  });

  test('failed browser launch keeps the authorization link available to copy',
      () async {
    const link = 'https://headscale.example.test/register/test-node';
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
        iosChannel,
        (call) async => call.method == 'tailnetStatus'
            ? jsonEncode({'state': 'NeedsLogin', 'authUrl': link})
            : null);
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(launcher, (_) async => false);
    await tailnet.authorize();
    expect(tailnet.error,
        'Could not open Tailscale authorization in the browser.');
    expect(tailnet.authorizationUri.toString(), link);
  });

  test('control server accepts official default and explicit Headscale URLs',
      () {
    for (final value in [
      '',
      'https://headscale.example.test',
      'http://192.168.1.2:8080'
    ]) {
      expect(validTailnetControlUrl(value), isTrue);
    }
    for (final value in [
      'headscale.example.test',
      'javascript:alert(1)',
      'https://user:secret@headscale.example.test',
      'https://headscale.example.test?key=secret'
    ]) {
      expect(validTailnetControlUrl(value), isFalse);
    }
  });
}
