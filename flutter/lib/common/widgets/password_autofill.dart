import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

bool get iosPasswordAutofillEnabled =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

Widget passwordAutofillGroup(Widget child) => iosPasswordAutofillEnabled
    ? AutofillGroup(
        onDisposeAction: AutofillContextAction.cancel,
        child: child,
      )
    : child;
