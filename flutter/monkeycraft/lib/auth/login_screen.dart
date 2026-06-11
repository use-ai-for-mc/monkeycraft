import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:monkeycraft_client/auth/credential_store.dart';
import 'package:monkeycraft_client/auth/qr_scan_screen.dart';
import 'package:monkeycraft_client/serverpicker/server_picker_screen.dart';
import 'package:monkeycraft_client/stream/screens/stream_screen.dart';
import 'package:monkeycraft_client/stream/stream_proxy.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serverController = TextEditingController();
  final _passController = TextEditingController();
  bool _isLoading = false;
  bool _connectInFlight = false;
  int _connectAttempt = 0;
  StreamProxy? _inFlightProxy;
  DateTime _lastConnectTapAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _loadCredentials();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.of(context)?.isCurrent == true) {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
    }
  }

  Future<void> _loadCredentials() async {
    final credentials = await CredentialStore.load();
    if (!mounted) return;
    setState(() {
      _serverController.text = credentials.server;
      _passController.text = credentials.password;
    });
  }

  Future<void> _saveCredentials() async {
    await CredentialStore.save(_serverController.text, _passController.text);
  }

  void _cancelConnect() {
    _connectAttempt += 1;
    _connectInFlight = false;
    setState(() => _isLoading = false);
    final proxy = _inFlightProxy;
    _inFlightProxy = null;
    if (proxy != null) {
      unawaited(proxy.stop().catchError((_) {}));
    }
  }

  void _exitApp() {
    if (Platform.isAndroid) {
      SystemNavigator.pop();
      return;
    }
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Exit is not supported on this platform')),
    );
  }

  Future<void> _connect() async {
    final now = DateTime.now();
    if (_connectInFlight) return;
    if (now.difference(_lastConnectTapAt) < const Duration(milliseconds: 800)) {
      return;
    }
    _lastConnectTapAt = now;
    if (!_formKey.currentState!.validate()) return;

    _connectInFlight = true;
    _connectAttempt += 1;
    final attempt = _connectAttempt;
    setState(() => _isLoading = true);
    await _saveCredentials();

    final proxy = StreamProxy();
    _inFlightProxy = proxy;
    try {
      await proxy
          .start(
            _serverController.text,
            _passController.text,
            connectTimeout: const Duration(seconds: 5),
            authTimeout: const Duration(seconds: 5),
          )
          .timeout(const Duration(seconds: 7));

      if (attempt != _connectAttempt) {
        await proxy.stop();
        return;
      }

      // The mod reports whether the client is already in a world. If it is at
      // a menu, show the server picker instead of the stream screen.
      final worldState = await proxy.awaitWorldState(
        timeout: const Duration(seconds: 2),
      );
      if (attempt != _connectAttempt) {
        await proxy.stop();
        return;
      }

      if (mounted) {
        final inWorld = worldState == null || worldState.isInWorld;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => inWorld
                ? StreamScreen(
                    proxy: proxy,
                    server: _serverController.text,
                    password: _passController.text,
                  )
                : ServerPickerScreen(
                    proxy: proxy,
                    server: _serverController.text,
                    password: _passController.text,
                  ),
          ),
        );
      }
    } catch (e) {
      await proxy.stop();
      if (attempt != _connectAttempt) {
        return;
      }
      if (mounted) {
        final msg = e is TimeoutException
            ? 'Connection timed out. Check server address and try again.'
            : 'Connection failed: $e';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (attempt == _connectAttempt) {
        _connectInFlight = false;
        _inFlightProxy = null;
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _serverController.dispose();
    _passController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    return Scaffold(
      appBar: AppBar(title: const Text('MonkeyCraft')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextFormField(
                  controller: _serverController,
                  decoration: const InputDecoration(
                    labelText: 'Server',
                    hintText: '192.168.0.3:9600 or example.ngrok-free.app',
                  ),
                  validator: (v) => v!.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passController,
                  decoration: InputDecoration(
                    labelText: 'Password (scan the QR code from the client)',
                    suffixIcon: IconButton(
                      onPressed: _isLoading
                          ? null
                          : () async {
                              final messenger = ScaffoldMessenger.of(context);
                              try {
                                final scanned = await Navigator.of(context)
                                    .push<String>(
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const QrScanScreen(),
                                      ),
                                    );
                                if (!mounted) return;
                                if (scanned == null) return;
                                setState(() => _passController.text = scanned);
                              } catch (e) {
                                if (!mounted) return;
                                messenger.showSnackBar(
                                  SnackBar(content: Text('Scan failed: $e')),
                                );
                              }
                            },
                      icon: const Icon(Icons.qr_code_scanner),
                      tooltip: 'Scan QR code',
                    ),
                  ),
                  obscureText: true,
                  validator: (v) => v!.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 32),
                if (Platform.isAndroid)
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isLoading ? _cancelConnect : _connect,
                          child: _isLoading
                              ? const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Text('Cancel'),
                                  ],
                                )
                              : const Text('Connect'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            if (_isLoading) _cancelConnect();
                            _exitApp();
                          },
                          child: const Text('Exit'),
                        ),
                      ),
                    ],
                  )
                else if (isPortrait)
                  ElevatedButton(
                    onPressed: _isLoading ? _cancelConnect : _connect,
                    child: _isLoading
                        ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 10),
                              Text('Cancel'),
                            ],
                          )
                        : const Text('Connect'),
                  )
                else
                  ElevatedButton(
                    onPressed: _isLoading ? _cancelConnect : _connect,
                    child: _isLoading
                        ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 10),
                              Text('Cancel'),
                            ],
                          )
                        : const Text('Connect'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
