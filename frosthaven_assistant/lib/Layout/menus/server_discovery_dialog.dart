import 'package:flutter/material.dart';
import 'package:frosthaven_assistant/services/network/client.dart';
import 'package:frosthaven_assistant/services/service_locator.dart';

class ServerDiscoveryDialog extends StatefulWidget {
  const ServerDiscoveryDialog({super.key});

  @override
  State<ServerDiscoveryDialog> createState() => _ServerDiscoveryDialogState();
}

class _ServerDiscoveryDialogState extends State<ServerDiscoveryDialog> {
  final _client = getIt<Client>();
  List<DiscoveredServer> _servers = [];
  bool _isDiscovering = false;

  @override
  void initState() {
    super.initState();
    _discoverServers();
  }

  void _discoverServers() {
    setState(() {
      _isDiscovering = true;
      _servers = [];
    });
    _client.discoverServers().listen((server) {
      setState(() {
        if (!_servers.any((s) => s.address == server.address && s.port == server.port)) {
          _servers.add(server);
        }
      });
    }).onDone(() {
      setState(() {
        _isDiscovering = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Discover Servers'),
      content: SizedBox(
        width: 400,
        height: 300,
        child: _isDiscovering && _servers.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _servers.isEmpty
                ? const Center(child: Text('No servers found.'))
                : ListView.builder(
                    itemCount: _servers.length,
                    itemBuilder: (context, index) {
                      final server = _servers[index];
                      return ListTile(
                        title: Text(server.name),
                        subtitle: Text('${server.address}:${server.port}'),
                        onTap: () {
                          Navigator.of(context).pop(server);
                        },
                      );
                    },
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _isDiscovering ? null : _discoverServers,
          child: const Text('Refresh'),
        ),
      ],
    );
  }
}
