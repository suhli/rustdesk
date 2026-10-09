import '../../models/platform_model.dart';
import 'orientation_policy.dart';
export 'orientation_policy.dart' show RemoteOrientation;

class IosPreferences {
  static bool get enhancedHome => read('home') != 'N';
  static bool get floatingToolbar => read('toolbar') != 'N';
  static bool get canvasGestures => read('canvas-gestures') != 'N';
  static bool get autoConnect => read('tailnet-auto') != 'N';
  static bool get authorized => read('tailnet-authorized') == 'Y';
  static RemoteOrientation get orientation => RemoteOrientation.values
      .firstWhere((mode) => mode.name == read('orientation'),
          orElse: () => RemoteOrientation.landscape);

  static String read(String key) => bind.getLocalFlutterOption(k: 'ios-$key');
  static Future<void> write(String key, String value) =>
      bind.setLocalFlutterOption(k: 'ios-$key', v: value);
}
