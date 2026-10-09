import 'package:flutter/material.dart';
import '../../common.dart';
import 'settings.dart';
import 'tailnet.dart';

class IosTailnetStatus extends StatelessWidget {
  const IosTailnetStatus({super.key});

  @override
  Widget build(BuildContext context) {
    final tailnet = EmbeddedTailnet.instance;
    return AnimatedBuilder(
        animation: tailnet,
        builder: (context, _) {
          if (!tailnet.enabled) return const SizedBox.shrink();
          final connecting =
              tailnet.state == 'Starting' || tailnet.state == 'NoState';
          final connected = tailnet.state == 'Running';
          final failed = tailnet.state == 'Failed' || tailnet.error.isNotEmpty;
          final color = failed
              ? Theme.of(context).colorScheme.error
              : connected
                  ? Colors.green
                  : tailnet.state == 'Stopped'
                      ? Theme.of(context).disabledColor
                      : Colors.orange;
          final detail = tailnet.error.isNotEmpty
              ? translate(tailnet.error)
              : connected
                  ? tailnet.ips
                  : '';
          return ListTile(
            dense: true,
            leading: connecting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(
                    failed
                        ? Icons.error_outline
                        : connected
                            ? Icons.check_circle_outline
                            : Icons.cloud_off,
                    color: color),
            title: Text('Tailnet · ${translate(tailnet.statusLabel)}'),
            subtitle: detail.isEmpty
                ? null
                : Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const IosSettingsPage())),
          );
        });
  }
}
