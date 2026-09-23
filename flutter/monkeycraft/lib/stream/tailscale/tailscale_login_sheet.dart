import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:monkeycraft_client/auth/credential_store.dart';
import 'package:monkeycraft_client/stream/tailscale/tailscale_embedded.dart';
import 'package:monkeycraft_client/stream/tailscale/tailscale_models.dart';

class TailscaleLoginResult {
  const TailscaleLoginResult({
    required this.nodeId,
    required this.displayName,
    required this.port,
  });

  final String nodeId;
  final String displayName;
  final int port;
}

class TailscaleLoginSheet extends StatefulWidget {
  const TailscaleLoginSheet({
    super.key,
    required this.client,
    this.savedNodeId,
    this.defaultPort = 9600,
    this.autoSelectSaved = false,
  });

  final TailscaleClient client;
  final String? savedNodeId;
  final int defaultPort;
  final bool autoSelectSaved;

  static Future<TailscaleLoginResult?> show(
    BuildContext context, {
    required TailscaleClient client,
    String? savedNodeId,
    int defaultPort = 9600,
    bool autoSelectSaved = false,
  }) {
    return showModalBottomSheet<TailscaleLoginResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) => TailscaleLoginSheet(
        client: client,
        savedNodeId: savedNodeId,
        defaultPort: defaultPort,
        autoSelectSaved: autoSelectSaved,
      ),
    );
  }

  @override
  State<TailscaleLoginSheet> createState() => _TailscaleLoginSheetState();
}

class _TailscaleLoginSheetState extends State<TailscaleLoginSheet> {
  StreamSubscription<TailscaleEmbeddedSnapshot>? _sub;
  TailscaleDiagnostics? _diagnostics;
  TailscaleEmbeddedSnapshot _snapshot = const TailscaleEmbeddedSnapshot(
    phase: 'stopped',
  );
  String? _savedNodeId;
  Object? _error;
  bool _busy = true;
  bool _keepNode = false;
  bool _cancelRequested = false;

  @override
  void initState() {
    super.initState();
    _savedNodeId = widget.savedNodeId;
    _sub = widget.client.events.listen((snapshot) {
      if (!mounted) return;
      setState(() => _snapshot = snapshot);
      _tryAutoSelect();
    });
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    try {
      final diagnostics = await widget.client.diagnostics();
      if (!mounted) return;
      setState(() => _diagnostics = diagnostics);
      if (!diagnostics.available) return;
      await widget.client.start();
      if (!mounted) return;
      final status = await widget.client.status();
      if (!mounted) return;
      setState(() => _snapshot = status);
      _tryAutoSelect();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (!_keepNode) _requestCancel();
    super.dispose();
  }

  void _requestCancel() {
    if (_cancelRequested) return;
    _cancelRequested = true;
    unawaited(widget.client.cancel().catchError((_) {}));
  }

  bool get _requestInFlight => _busy || _snapshot.phase == 'starting';

  bool get _showSpinner =>
      _requestInFlight || (!kIsWeb && _snapshot.needsLogin && !_hasAuthUrl);

  bool get _hasAuthUrl => _snapshot.authUrlHost?.isNotEmpty ?? false;

  String get _statusText {
    if (_diagnostics != null && !_diagnostics!.available) {
      return _diagnostics!.reason;
    }
    switch (_snapshot.phase) {
      case 'starting':
        return kIsWeb
            ? 'Preparing your secure connection… This may take a moment the first time.'
            : 'Starting embedded Tailscale…';
      case 'needsLogin':
        if (_snapshot.errorCode == 'auth_url_open_failed') {
          return _snapshot.errorMessage ??
              'Could not open the Tailscale sign-in page. Tap to try again.';
        }
        if (kIsWeb && !_hasAuthUrl) {
          return 'Sign in with your Tailscale account to find your game computer.';
        }
        if (!_hasAuthUrl) {
          return 'Preparing Tailscale sign-in. The sign-in page will open automatically. Keep this screen open while Tailscale responds.';
        }
        return 'Finish signing in with Tailscale, then return here. You can open Tailscale login again if the page did not appear.';
      case 'needsApproval':
        return 'This device is waiting for a tailnet admin to approve it. If you signed into the wrong account, sign out and try again.';
      case 'running':
        return 'Choose the computer running MonkeyCraft.';
      case 'failed':
        return _snapshot.errorMessage ?? 'Embedded Tailscale failed.';
      case 'unavailable':
        return _snapshot.errorMessage ?? 'Embedded Tailscale is unavailable.';
      default:
        return 'Embedded Tailscale is stopped.';
    }
  }

  Future<void> _retry() async {
    if (_busy || (!kIsWeb && _snapshot.needsLogin && !_hasAuthUrl)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!kIsWeb) {
        await widget.client.start();
        if (!mounted) return;
      }
      await widget.client.loginInteractive();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelLogin() async {
    _requestCancel();
    if (mounted) Navigator.of(context).pop();
  }

  bool get _canLogout {
    switch (_snapshot.phase) {
      case 'starting':
      case 'needsLogin':
      case 'needsApproval':
      case 'running':
      case 'failed':
        return true;
      default:
        return false;
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out of Tailscale?'),
        content: const Text(
          'This deletes the embedded node on this device so you can sign in with a different account. Direct/LAN connect still works.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep signed in'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out and delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await CredentialStore.saveTailscaleNodeId(null);
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _savedNodeId = null;
    });
    try {
      await widget.client.logout();
      if (!mounted) return;
      setState(() {
        _snapshot = const TailscaleEmbeddedSnapshot(phase: 'stopped');
      });
      await widget.client.start();
      if (!mounted) return;
      if (!kIsWeb) await widget.client.loginInteractive();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _tryAutoSelect() {
    if (!widget.autoSelectSaved || _keepNode || !_snapshot.isRunning) return;
    final matches = _snapshot.peers.where(
      (p) => p.nodeId == _savedNodeId && p.online,
    );
    if (matches.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_keepNode) _selectPeer(matches.first);
    });
  }

  void _selectPeer(TailscalePeer peer) {
    _keepNode = true;
    Navigator.of(context).pop(
      TailscaleLoginResult(
        nodeId: peer.nodeId,
        displayName: peer.displayName,
        port: widget.defaultPort,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final peers = _snapshot.peers;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Connect with Tailscale',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(_statusText),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  '$_error',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              if (_showSpinner) ...[
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 16),
              ],
              if ((_snapshot.needsLogin && (kIsWeb || _hasAuthUrl)) ||
                  _snapshot.phase == 'failed' ||
                  _snapshot.phase == 'stopped')
                ElevatedButton(
                  onPressed: _requestInFlight ? null : _retry,
                  child: Text(
                    _snapshot.needsLogin && _hasAuthUrl
                        ? 'Open Tailscale login again'
                        : 'Open Tailscale login',
                  ),
                ),
              if (_snapshot.isRunning && peers.isEmpty)
                const Text('No other devices are visible on this tailnet yet.'),
              if (_snapshot.isRunning)
                ...peers.map((peer) {
                  final sameName =
                      peers
                          .where((p) => p.displayName == peer.displayName)
                          .length >
                      1;
                  final address = sameName ? peer.addressSummary : null;
                  return ListTile(
                    leading: const Icon(Icons.computer),
                    title: Text(peer.displayName),
                    subtitle: Text(
                      address == null
                          ? (peer.online ? 'Online' : 'Offline')
                          : '${peer.online ? 'Online' : 'Offline'} · $address',
                    ),
                    selected: peer.nodeId == _savedNodeId,
                    onTap: () => _selectPeer(peer),
                  );
                }),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(
                    onPressed: _cancelLogin,
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  if (_canLogout)
                    TextButton(
                      onPressed: _requestInFlight ? null : _logout,
                      child: const Text('Sign out and retry'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
