import 'dart:async';

import 'package:flutter/material.dart';
import 'package:monkeycraft_client/shared/protocol_models.dart';
import 'package:monkeycraft_client/stream/screens/stream_screen.dart';
import 'package:monkeycraft_client/stream/stream_proxy.dart';

/// Shown when the app connects while Minecraft is still at a menu (no world
/// joined). Lets the player pick a saved multiplayer server or type an address,
/// then hands off to [StreamScreen] once the client is in a world.
class ServerPickerScreen extends StatefulWidget {
  final StreamProxy proxy;
  final String server;
  final String password;

  const ServerPickerScreen({
    super.key,
    required this.proxy,
    required this.server,
    required this.password,
  });

  @override
  State<ServerPickerScreen> createState() => _ServerPickerScreenState();
}

class _ServerPickerScreenState extends State<ServerPickerScreen> {
  final _addressController = TextEditingController();

  List<ServerListEntry> _servers = const [];
  bool _loadingList = true;
  bool _joining = false;
  String? _joiningLabel;
  bool _navigated = false;

  StreamSubscription<List<ServerListEntry>>? _serverListSub;
  StreamSubscription<WorldState>? _worldStateSub;
  StreamSubscription<JoinResult>? _joinResultSub;
  StreamSubscription<void>? _connectionLostSub;

  @override
  void initState() {
    super.initState();
    _serverListSub = widget.proxy.serverListEvents.listen((servers) {
      if (!mounted) return;
      setState(() {
        _servers = servers;
        _loadingList = false;
      });
    });
    _worldStateSub = widget.proxy.worldStateEvents.listen(_handleWorldState);
    _joinResultSub = widget.proxy.joinResultEvents.listen(_handleJoinResult);
    _connectionLostSub = widget.proxy.connectionLostEvents.listen(
      (_) => _returnToLogin('Connection lost'),
    );

    // If the client raced ahead into a world before this screen opened.
    final current = widget.proxy.worldState;
    if (current != null && current.isInWorld) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _goToStream());
    }

    widget.proxy.requestServerList();
  }

  void _handleWorldState(WorldState state) {
    if (state.isInWorld) {
      _goToStream();
      return;
    }
    // A join was accepted but the client bounced back to a menu (connect failed).
    if (state.isMenu && _joining && mounted) {
      setState(() {
        _joining = false;
        _joiningLabel = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not connect to that server')),
      );
    }
  }

  void _handleJoinResult(JoinResult result) {
    if (!mounted || result.ok) return;
    setState(() {
      _joining = false;
      _joiningLabel = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.error ?? 'Failed to join server')),
    );
  }

  void _join(String address, String label) {
    if (_joining) return;
    final trimmed = address.trim();
    if (trimmed.isEmpty) return;
    final name = label.trim().isEmpty ? trimmed : label.trim();
    setState(() {
      _joining = true;
      _joiningLabel = name;
    });
    widget.proxy.joinServer(trimmed, name: name);
  }

  void _refresh() {
    setState(() => _loadingList = true);
    widget.proxy.requestServerList();
  }

  void _goToStream() {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => StreamScreen(
          proxy: widget.proxy,
          server: widget.server,
          password: widget.password,
        ),
      ),
    );
  }

  Future<void> _returnToLogin(String message) async {
    if (_navigated || !mounted) return;
    _navigated = true;
    await widget.proxy.stop();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  void dispose() {
    _serverListSub?.cancel();
    _worldStateSub?.cancel();
    _joinResultSub?.cancel();
    _connectionLostSub?.cancel();
    // If we are leaving this screen without handing the connection off to the
    // stream screen (e.g. system back button), close the connection.
    if (!_navigated) {
      widget.proxy.stop();
    }
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose a server'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Disconnect',
          onPressed: _joining ? null : () => _returnToLogin('Disconnected'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _joining ? null : _refresh,
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildBody(),
          if (_joining)
            Positioned.fill(
              child: AbsorbPointer(
                child: ColoredBox(
                  color: Colors.black54,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          'Joining ${_joiningLabel ?? 'server'}...',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Saved servers',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        if (_loadingList)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_servers.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('No saved servers on this Minecraft client.'),
          )
        else
          ..._servers.map(
            (s) => Card(
              child: ListTile(
                title: Text(s.name.isEmpty ? s.address : s.name),
                subtitle: Text(s.address),
                trailing: const Icon(Icons.play_arrow),
                onTap: () => _join(s.address, s.name),
              ),
            ),
          ),
        const Divider(height: 32),
        const Text(
          'Direct connect',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _addressController,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Server address',
            hintText: 'play.example.com or 192.168.1.5:25565',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => _join(value, ''),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _join(_addressController.text, ''),
            icon: const Icon(Icons.login),
            label: const Text('Join server'),
          ),
        ),
      ],
    );
  }
}
