import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:monkeycraft_client/screens/qr_scan_screen.dart';
import 'package:monkeycraft_client/screens/stream_screen.dart';
import 'package:monkeycraft_client/services/stream_proxy.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
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
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hostController.text = prefs.getString('host') ?? '127.0.0.1';
      _portController.text = prefs.getString('port') ?? '9600';
      _passController.text = prefs.getString('password') ?? '';
    });
  }

  Future<void> _saveCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('host', _hostController.text);
    await prefs.setString('port', _portController.text);
    await prefs.setString('password', _passController.text);
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
      await proxy.start(
        _hostController.text,
        int.parse(_portController.text),
        _passController.text,
        connectTimeout: const Duration(seconds: 5),
        authTimeout: const Duration(seconds: 5),
      ).timeout(const Duration(seconds: 7));

      if (attempt != _connectAttempt) {
        await proxy.stop();
        return;
      }

      if (mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => StreamScreen(proxy: proxy),
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
            ? 'Connection timed out. Check host/port and try again.'
            : 'Connection failed: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
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
    _hostController.dispose();
    _portController.dispose();
    _passController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    return Scaffold(
      appBar: AppBar(
        title: const Text('MonkeyCraft'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextFormField(
                  controller: _hostController,
                  decoration: const InputDecoration(labelText: 'Host (IP or domain)'),
                  validator: (v) => v!.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _portController,
                  decoration: const InputDecoration(labelText: 'Port'),
                  keyboardType: TextInputType.number,
                  validator: (v) => v!.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passController,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      onPressed: _isLoading
                          ? null
                          : () async {
                              try {
                                final scanned = await Navigator.of(context).push<String>(
                                  MaterialPageRoute(
                                    builder: (context) => const QrScanScreen(),
                                  ),
                                );
                                if (!mounted) return;
                                if (scanned == null) return;
                                setState(() => _passController.text = scanned);
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
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
                if (isPortrait) ...[
                  ElevatedButton(
                    onPressed: _isLoading ? _cancelConnect : _connect,
                    child: _isLoading
                        ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 10),
                              Text('Cancel'),
                            ],
                          )
                        : const Text('Connect'),
                  ),
                  if (Platform.isAndroid) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () {
                        if (_isLoading) _cancelConnect();
                        _exitApp();
                      },
                      child: const Text('Exit'),
                    ),
                  ],
                ] else ...[
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
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                    SizedBox(width: 10),
                                    Text('Cancel'),
                                  ],
                                )
                              : const Text('Connect'),
                        ),
                      ),
                      if (Platform.isAndroid) ...[
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
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
