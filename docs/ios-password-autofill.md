# iOS Password AutoFill

This change enables the standard iOS password picker for Console/address-book
account login and remote device access passwords. It uses Flutter's existing
input widgets, without a password-manager SDK or a change to authentication.

## Input fields

- `LoginWidgetUserPass` places the existing username and password fields in one
  `AutofillGroup`, with `AutofillHints.username` and `AutofillHints.password`.
- `PasswordWidget` forwards its optional `autofillHints` through
  `DialogTextField` to the actual `TextField`. Both wrapper parameters default
  to null. Without a supplied hint, the underlying field keeps its original
  empty-list default, including on Android, desktop and web.
- `_connectDialog` puts only the RustDesk device-access password in a separate
  password-only group. It does not add a username or combine the access password
  with the remote OS account fields. The same original controller feeds
  `gFFI.login` and `sessionLogin`, including the existing trimming and remember
  flag. Temporary and permanent passwords continue through the existing path.
- OS login, elevation credentials, OS-password configuration, and verification
  code fields are not enabled by this change. These are different credentials
  or verification factors; grouping them with a device or Console password could
  select or replace the wrong secret.

The feature gate uses Flutter's native iOS target and excludes web. It does not
change keyboard type, autocorrection, suggestions, initial values, focus nodes,
validation, or password visibility controls.

## Context lifetime and saving policy

Each mounted form owns a group. Rebuilds and focus changes reuse that group and
the original controllers. `loginDialog()` retains its existing guard against
opening a second simultaneous login dialog.

All groups use `AutofillContextAction.cancel` on disposal. Closing or cancelling
a form therefore ends the context with `shouldSave: false`. Authentication
failure leaves the group and the entered values intact.

For Console username/password login, the code requests
`TextInput.finishAutofillContext(shouldSave: true)` only after an access-token
response and the existing token-storage calls have succeeded. The dialog must
still be open and both controllers must still match the submitted values. An
OIDC success does not commit an unfinished username/password form.

Two cases deliberately do not request credential saving:

1. Remote-device authentication is asynchronous: the password dialog closes
   before the remote endpoint confirms the password. Closing it submits the
   existing connection request and cancels the AutoFill context. This avoids
   saving an unverified or temporary password and leaves RustDesk's own remember
   option unchanged.
2. On mobile, Console email/TOTP verification closes the password dialog before
   opening the verification dialog. Its AutoFill context is cancelled at that
   handoff. Filling existing credentials works; this change does not retain the
   password context across the second-factor flow to offer saving afterward.

`shouldSave: true` is a request to the platform, not a guarantee of a save prompt.
No Associated Domains, entitlements, Info.plist entries, signing settings, or
deployment targets are added. The existing iOS deployment target is 13.0.
Without a verified associated domain, manually selecting existing passwords is
the intended first step; domain-matched suggestions and saving/updating are not
guaranteed. See Flutter's [TextField AutoFill documentation](https://api.flutter.dev/flutter/material/TextField/autofillHints.html)
and [context lifecycle documentation](https://api.flutter.dev/flutter/services/TextInput/finishAutofillContext.html).

## Automated checks

Use the iOS workflow's Flutter 3.24.5 and the generated bridge files from the
same source revision (or generate them with the existing bridge workflow).

```sh
cd flutter
flutter pub get
flutter test test/password_autofill_test.dart
```

Validated on Windows with Flutter 3.24.5 / Dart 3.5.4: all 10 AutoFill widget
cases and the existing `server_settings_dialog_test.dart` regression test
passed (11 total). Targeted static analysis reported no errors or warnings;
the five informational deprecation notices are in unchanged `dialog.dart` code.

The widget tests send `TextInputClient.updateEditingStateWithTag`, the platform
AutoFill message, into the real input widgets. A test bridge replaces native
calls so tests can exercise the existing Console HTTP-response handling and
remote `sessionLogin` arguments without a server or saved user credentials.
`PlatformFFI.ffiBind` has a testing-only setter for this purpose; application
initialization continues to create the native bridge as before.

The automated cases cover grouped hints, platform-driven controller updates,
password visibility, failed login and successful retry, cancellation/reopening,
editing while a request is pending, OIDC isolation, device passwords with the
remember option off/on, separate OS credentials, and unchanged defaults on
Android and Windows. They verify the existing authentication request arguments,
not a real server's temporary/permanent password verification.

## Device validation — pending

Windows widget tests cannot validate iOS's keyboard UI or a credential provider.
The following must be checked on the requested iOS 27.2 device, separately with
1Password and iCloud Passwords, and then on an older supported iOS version:

- Enable the chosen password AutoFill provider and create a disposable test
  credential. Focus the Console username/password fields and open the keyboard
  password picker. Confirm both values fill and visibility toggling preserves
  them.
- Test a failed password, a successful retry, cancellation, repeated opening,
  and an incomplete form followed by OIDC. Failed or cancelled login must not
  offer to save invalid credentials.
- On successful password login, check whether the provider offers saving or
  updating; record the provider's actual behavior without assuming a prompt.
- Test email/TOTP handoff and cancellation. No save request is made by the
  password form at that handoff.
- Connect using a temporary device password and then a permanent password,
  with remember off and on. Select the password in 1Password. For the combined
  OS/device dialog, ensure device filling leaves the OS credentials alone.
- If testing through LiveContainer, record its version and signing/container
  setup separately; credential-provider behavior there is also unverified.

No iOS device, provider UI, IPA build, or signing verification has been performed
by the Windows widget tests.
