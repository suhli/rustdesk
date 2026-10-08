import 'package:flutter/services.dart';
import 'preferences.dart';
import 'orientation_policy.dart';

const iosChannel = MethodChannel('rustdesk/ios-enhancements');

/// Queue entry/exit requests: a late native response must not rotate the home page.
class RemoteOrientationController {
  Future<void> _pending = Future.value();
  bool inSession = false;
  Future<String?> home() => _apply(IosPreferences.orientation, false);
  Future<String?> enter() {
    inSession = true;
    return _apply(IosPreferences.orientation, true);
  }

  Future<String?> leave() {
    inSession = false;
    return home();
  }

  Future<String?> rotate(bool landscape) => _apply(
      landscape ? RemoteOrientation.landscape : RemoteOrientation.portrait,
      true,
      explicit: true);

  Future<String?> _apply(RemoteOrientation mode, bool session,
      {bool explicit = false}) async {
    String? error;
    final request = _pending.then((_) async {
      if (session && !inSession) return;
      try {
        final tablet = await iosChannel.invokeMethod<bool>('isTablet') ?? false;
        final orientations = orientationPolicy(mode,
            session: session, tablet: tablet, explicit: explicit);
        await SystemChrome.setPreferredOrientations(orientations);
        await iosChannel.invokeMethod(
            'orientation',
            orientations.length == 1
                ? 'portrait'
                : orientations.length == 2
                    ? 'landscape'
                    : 'system');
      } on PlatformException catch (e) {
        error = e.message ?? e.code;
      } on MissingPluginException {
        error = 'Orientation control is unavailable in this build.';
      }
    });
    _pending = request;
    await request;
    return error;
  }
}

final iosOrientation = RemoteOrientationController();
