import 'package:flutter/material.dart';
import '../../common.dart';
import '../../models/platform_model.dart';
import 'orientation.dart';
import 'preferences.dart';
import 'tailnet.dart';

class IosSettingsPage extends StatefulWidget {
  const IosSettingsPage({super.key});
  @override
  State<IosSettingsPage> createState() => _IosSettingsPageState();
}

class _IosSettingsPageState extends State<IosSettingsPage> {
  final tailnet = EmbeddedTailnet.instance;
  static const orientationLabels = [
    'Automatic landscape',
    'Follow system',
    'Always portrait',
    'Manual rotation'
  ];

  Widget _heading(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Text(translate(label),
          style: Theme.of(context).textTheme.titleSmall));
  Widget _switch(String label, bool value, ValueChanged<bool>? change,
          {String? detail}) =>
      SwitchListTile(
          title: Text(translate(label)),
          value: value,
          onChanged: change,
          subtitle: detail == null ? null : Text(translate(detail)));

  Future<void> _set(String key, bool value) async {
    await IosPreferences.write(key, value ? 'Y' : 'N');
    if (mounted) setState(() {});
  }

  Future<void> _forget({bool reconnect = false}) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(translate(
                  reconnect ? 'Authorize a new node' : 'Clear local identity')),
              content: Text(translate(
                  'This removes this app’s saved Tailscale identity. The device may remain in the Tailscale admin console; remove it there separately.')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(translate('Cancel'))),
                TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(translate('Continue')))
              ],
            ));
    if (confirmed != true) return;
    await tailnet.forget();
    if (reconnect && tailnet.error.isEmpty) await tailnet.connect();
  }

  Future<void> _alternate(String service) async {
    final key = 'ios-tailnet-$service-alternate';
    final controller =
        TextEditingController(text: bind.mainGetOptionSync(key: key));
    final value = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(translate('Alternate server')),
              content: TextField(
                  controller: controller,
                  autocorrect: false,
                  decoration: InputDecoration(
                      labelText: service == 'api'
                          ? 'https://host:port'
                          : 'host:port')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(translate('Cancel'))),
                TextButton(
                    onPressed: () =>
                        Navigator.pop(context, controller.text.trim()),
                    child: Text(translate('Save')))
              ],
            ));
    controller.dispose();
    if (value == null) return;
    if (value.isNotEmpty) {
      final uri = Uri.tryParse(service == 'api' ? value : 'tcp://$value');
      if (uri == null ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          (service == 'api' && uri.scheme != 'http' && uri.scheme != 'https') ||
          (service != 'api' && uri.path.isNotEmpty)) {
        showToast(translate('Invalid server address'));
        return;
      }
    }
    await bind.mainSetOption(key: key, value: value);
    if (mounted) setState(() {});
  }

  String get _status {
    if (!tailnet.enabled) return 'Not enabled';
    switch (tailnet.state) {
      case 'Running':
        return 'Connected';
      case 'NeedsLogin':
        return 'Authorization required';
      case 'NeedsMachineAuth':
        return 'Approve this device in the Tailscale admin console';
      case 'Starting':
      case 'NoState':
        return 'Connecting...';
      case 'Failed':
        return 'Connection failed';
      default:
        return 'Disconnected';
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(translate('iOS enhancements'))),
        body: AnimatedBuilder(
            animation: tailnet,
            builder: (context, _) => ListView(children: [
                  _heading('Display and orientation'),
                  ListTile(
                      title: Text(translate('Remote session orientation')),
                      subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(translate(
                                'Automatic landscape applies to iPhone. iPad keeps its system orientation.')),
                            DropdownButton<RemoteOrientation>(
                                isExpanded: true,
                                value: IosPreferences.orientation,
                                items: RemoteOrientation.values
                                    .map((mode) => DropdownMenuItem(
                                        value: mode,
                                        child: Text(translate(
                                            orientationLabels[mode.index]))))
                                    .toList(),
                                onChanged: (mode) async {
                                  if (mode == null) return;
                                  await IosPreferences.write(
                                      'orientation', mode.name);
                                  if (mounted) setState(() {});
                                  final error = await iosOrientation.home();
                                  if (error != null && mounted) {
                                    showToast(translate(error));
                                  }
                                })
                          ])),
                  _switch('Address book home', IosPreferences.enhancedHome,
                      (v) => _set('home', v)),
                  _switch('Floating session toolbar',
                      IosPreferences.floatingToolbar, (v) => _set('toolbar', v),
                      detail: 'Applies to the next remote session.'),
                  _heading('Tailscale'),
                  _switch('Enable embedded Tailscale', tailnet.enabled,
                      tailnet.busy ? null : tailnet.setEnabled,
                      detail:
                          'Creates an independent node for this app. No system VPN is used.'),
                  ListTile(
                      leading: Icon(tailnet.state == 'Running'
                          ? Icons.check_circle_outline
                          : Icons.cloud_off),
                      title: Text(translate(_status)),
                      subtitle: tailnet.name.isEmpty
                          ? null
                          : Text('${tailnet.name}\n${tailnet.ips}')),
                  if (tailnet.busy) const LinearProgressIndicator(),
                  if (tailnet.error.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(translate(tailnet.error),
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))),
                  _switch('Connect on app launch', IosPreferences.autoConnect,
                      tailnet.busy ? null : (v) => _set('tailnet-auto', v)),
                  Wrap(spacing: 8, children: [
                    TextButton(
                        onPressed: !tailnet.enabled || tailnet.busy
                            ? null
                            : tailnet.connect,
                        child: Text(translate('Connect'))),
                    TextButton(
                        onPressed: !tailnet.enabled || tailnet.busy
                            ? null
                            : tailnet.authorize,
                        child: Text(translate('Authorize'))),
                    TextButton(
                        onPressed: !tailnet.enabled || tailnet.busy
                            ? null
                            : tailnet.disconnect,
                        child: Text(translate('Disconnect'))),
                    TextButton(
                        onPressed: !tailnet.enabled || tailnet.busy
                            ? null
                            : () => _forget(reconnect: true),
                        child: Text(translate('Authorize a new node'))),
                    TextButton(
                        onPressed: tailnet.busy ? null : _forget,
                        child: Text(translate('Clear local identity'))),
                  ]),
                  _heading('Network routing'),
                  _switch(
                      'Console API through Tailscale',
                      tailnet.apiEnabled,
                      tailnet.busy
                          ? null
                          : (v) => tailnet.setRoute(tailnetApiKey, v),
                      detail:
                          'Uses the explicit API Server from ID/Relay Server settings. Reconnect after changing server addresses.'),
                  _switch(
                      'ID server through Tailscale',
                      tailnet.routeEnabled(tailnetIdKey),
                      tailnet.busy
                          ? null
                          : (v) => tailnet.setRoute(tailnetIdKey, v),
                      detail:
                          'TCP signaling and online queries. Remote sessions use relay mode; UDP and P2P are not tunneled.'),
                  _switch(
                      'Relay server through Tailscale',
                      tailnet.routeEnabled(tailnetRelayKey),
                      tailnet.busy
                          ? null
                          : (v) => tailnet.setRoute(tailnetRelayKey, v),
                      detail:
                          'Uses the explicit Relay Server. It must match the server advertised by your ID Server.'),
                  ListTile(
                      title: Text(translate('Connection failure')),
                      subtitle: Text(translate(
                          'Wait for Tailscale and retry. Private requests are never automatically sent through the public ID Server.'))),
                  _switch(
                      'Use configured alternate servers',
                      bind.mainGetOptionSync(key: tailnetFallbackKey) ==
                          'alternate',
                      tailnet.busy ? null : tailnet.setFallback,
                      detail:
                          'When disconnected, only these explicit addresses may receive requests and account credentials. Failed in-flight requests are not replayed; disconnect and retry to use an alternate.'),
                  if (bind.mainGetOptionSync(key: tailnetFallbackKey) ==
                      'alternate')
                    for (final service in ['api', 'id', 'relay'])
                      ListTile(
                          title: Text(
                              '${service.toUpperCase()} — ${translate('Alternate server')}'),
                          subtitle: Text(bind.mainGetOptionSync(
                              key: 'ios-tailnet-$service-alternate')),
                          trailing: const Icon(Icons.edit_outlined),
                          onTap: () => _alternate(service)),
                  ListTile(
                      title: Text(translate('Test private API')),
                      subtitle: Text(translate(tailnet.apiStatus)),
                      trailing: const Icon(Icons.network_check),
                      onTap: tailnet.enabled &&
                              tailnet.apiEnabled &&
                              !tailnet.busy &&
                              tailnet.state == 'Running'
                          ? tailnet.testApi
                          : null),
                  const SizedBox(height: 24),
                ])),
      );
}
