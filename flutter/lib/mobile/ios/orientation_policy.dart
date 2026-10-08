import 'package:flutter/services.dart';

enum RemoteOrientation { landscape, system, portrait, manual }

List<DeviceOrientation> orientationPolicy(RemoteOrientation mode,
    {required bool session, required bool tablet, bool explicit = false}) {
  if ((tablet && !explicit) || mode == RemoteOrientation.system) {
    return DeviceOrientation.values;
  }
  if (session && mode == RemoteOrientation.landscape) {
    return [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight];
  }
  return [DeviceOrientation.portraitUp];
}
