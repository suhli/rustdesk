import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/mobile/ios/orientation_policy.dart';

void main() {
  test('iPhone enters landscape and returns to portrait', () {
    expect(
        orientationPolicy(RemoteOrientation.landscape,
            session: true, tablet: false),
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    expect(
        orientationPolicy(RemoteOrientation.landscape,
            session: false, tablet: false),
        [DeviceOrientation.portraitUp]);
  });
  test('iPad and follow-system preserve all orientations', () {
    expect(
        orientationPolicy(RemoteOrientation.landscape,
            session: true, tablet: true),
        DeviceOrientation.values);
    expect(
        orientationPolicy(RemoteOrientation.system,
            session: false, tablet: false),
        DeviceOrientation.values);
    expect(
        orientationPolicy(RemoteOrientation.landscape,
            session: true, tablet: true, explicit: true),
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  });
  test('portrait and manual modes do not rotate on connection', () {
    for (final mode in [RemoteOrientation.portrait, RemoteOrientation.manual]) {
      expect(orientationPolicy(mode, session: true, tablet: false),
          [DeviceOrientation.portraitUp]);
    }
  });
}
