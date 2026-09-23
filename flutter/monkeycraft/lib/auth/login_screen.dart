import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:monkeycraft_client/auth/credential_store.dart';
import 'package:monkeycraft_client/auth/login_auth_policy.dart';
import 'package:monkeycraft_client/auth/pairing_eligibility.dart';
import 'package:monkeycraft_client/auth/web_origin_server.dart';
import 'package:monkeycraft_client/auth/qr_scan_screen.dart';
import 'package:monkeycraft_client/platform/platform_capabilities.dart';
import 'package:monkeycraft_client/serverpicker/server_picker_screen.dart';
import 'package:monkeycraft_client/stream/connection_endpoint.dart';
import 'package:monkeycraft_client/stream/screens/stream_screen.dart';
import 'package:monkeycraft_client/stream/stream_proxy.dart';
import 'package:monkeycraft_client/stream/tailscale/tailscale_embedded.dart';
import 'package:monkeycraft_client/stream/tailscale/tailscale_login_sheet.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.platformCapabilitiesOverride,
    this.tailscaleClient,
  });

  final PlatformCapabilities? platformCapabilitiesOverride;
  final TailscaleClient? tailscaleClient;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _serverController = TextEditingController();
  final _passController = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _isLoading = false;
  bool _autoConnecting = false;
  bool _editServer = true;
  bool _connectInFlight = false;
  int _connectAttempt = 0;
  StreamProxy? _inFlightProxy;
  DateTime _lastConnectTapAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _savedTailscaleNodeId;
  String? _bridgeLeaseId;
  bool _rememberCredentials = true;
  LoginAuthMode _mode = LoginAuthMode.password;
  bool _passwordVisible = false;
  PairingCode? _pairingCode;
  Timer? _clipboardClearTimer;
  String? _copiedPassword;
  late final TailscaleClient _tailscale;

  PlatformCapabilities get _platformCapabilities =>
      widget.platformCapabilitiesOverride ?? platformCapabilities;

  @override
  void initState() {
    super.initState();
    _tailscale = widget.tailscaleClient ?? TailscaleEmbeddedClient();
    WidgetsBinding.instance.addObserver(this);
    _serverController.addListener(_onServerChanged);
    _passController.addListener(_onPasswordChanged);
    _passwordFocus.addListener(_onPasswordFocusChanged);
    _loadCredentials(connectOnLaunch: kIsWeb);
  }

  final _webPasswordAutofill = WebPasswordAutofill('');
  bool _settingAutofilledPassword = false;

  void _onServerChanged() {
    if (kIsWeb && _webPasswordAutofill.clearForTarget(_serverController.text)) {
      _passController.clear();
    }
    _onFieldsChanged();
  }

  void _onPasswordChanged() {
    if (!_settingAutofilledPassword) _webPasswordAutofill.clear();
    _onFieldsChanged();
  }

  void _onFieldsChanged() {
    if (_passController.text.isNotEmpty) {
      _mode = LoginAuthMode.password;
    } else if (_mode == LoginAuthMode.pair && !_addressPairingEligible) {
      _mode = LoginAuthMode.password;
    }
    if (mounted) setState(() {});
  }

  void _onPasswordFocusChanged() {
    if (!_passwordFocus.hasFocus && _passwordVisible && mounted) {
      setState(() => _passwordVisible = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (_passwordVisible && mounted) {
        setState(() => _passwordVisible = false);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.of(context)?.isCurrent == true) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarContrastEnforced: false,
        ),
      );
    }
  }

  Future<void> _loadCredentials({bool connectOnLaunch = false}) async {
    final credentials = await CredentialStore.load();
    if (!mounted) return;
    setState(() {
      final server = kIsWeb
          ? webInitialServer(Uri.base, credentials.server)
          : credentials.server;
      _serverController.text = server;
      _editServer = !kIsWeb || server.isEmpty;
      _settingAutofilledPassword = true;
      _passController.text = credentials.password;
      _settingAutofilledPassword = false;
      _webPasswordAutofill.clear();
      if (kIsWeb && credentials.password.isNotEmpty) {
        _webPasswordAutofill.setTarget(server);
      }
      _savedTailscaleNodeId = credentials.tailscaleNodeId;
      _rememberCredentials = credentials.rememberCredentials;
      _mode = LoginAuthPolicy.defaultMode(
        hasPassword: credentials.password.isNotEmpty,
        addressPairingEligible: isPairingEligibleServer(server),
      );
    });
    if (connectOnLaunch &&
        credentials.rememberCredentials &&
        credentials.webPreferTailscale &&
        credentials.tailscaleNodeId != null &&
        _tailscale.isSupported) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _connectAttempt == 0) {
          unawaited(_connectEmbeddedTailscale(autoSelectSaved: true));
        }
      });
      return;
    }
    if (connectOnLaunch &&
        credentials.rememberCredentials &&
        _hasPassword &&
        webServerError(Uri.base, _serverController.text) == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _connectAttempt != 0) return;
        setState(() => _autoConnecting = true);
        unawaited(_connect());
      });
    }
  }

  Future<void> _saveCredentials() async {
    await CredentialStore.saveRememberCredentials(_rememberCredentials);
    if (_rememberCredentials) {
      await CredentialStore.save(
        _serverController.text,
        kIsWeb ? '' : _passController.text,
      );
    } else {
      await CredentialStore.save(_serverController.text, '');
      await CredentialStore.clearPassword();
    }
  }

  Future<void> _persistPairedPassword(String password) async {
    _webPasswordAutofill.clear();
    _passController.text = password;
    if (_rememberCredentials && !kIsWeb) {
      await CredentialStore.save(_serverController.text, password);
    }
  }

  bool get _hasPassword => _passController.text.isNotEmpty;

  bool get _addressPairingEligible =>
      isPairingEligibleServer(_serverController.text);

  bool get _showPasswordField =>
      LoginAuthPolicy.showPasswordField(mode: _mode, hasPassword: _hasPassword);

  void _cancelConnect() {
    _connectAttempt += 1;
    _connectInFlight = false;
    setState(() {
      _isLoading = false;
      _autoConnecting = false;
      _pairingCode = null;
    });
    final proxy = _inFlightProxy;
    _inFlightProxy = null;
    if (proxy != null) {
      unawaited(proxy.stop().catchError((_) {}));
    }
    _closeBridge();
  }

  void _closeBridge() {
    final leaseId = _bridgeLeaseId;
    _bridgeLeaseId = null;
    if (leaseId != null) {
      unawaited(_tailscale.closeBridge(leaseId).catchError((_) {}));
    }
  }

  void _exitApp() {
    if (_platformCapabilities.isAndroid) {
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

  Future<void> _scanPassword() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final scanned = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (context) => const QrScanScreen()),
      );
      if (!mounted) return;
      if (scanned == null) return;
      setState(() {
        _passController.text = scanned;
        _mode = LoginAuthMode.password;
      });
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Scan failed: $e')));
    }
  }

  Widget _connectButton({
    required VoidCallback? onPressed,
    required bool expanded,
  }) {
    final child = _isLoading
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
        : const Text('Connect');
    final button = ElevatedButton(onPressed: onPressed, child: child);
    if (expanded) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }

  Future<void> _connect({
    String? overrideServer,
    bool saveServer = true,
    bool tailscalePath = false,
    ConnectionEndpoint? endpoint,
    String? passwordOverride,
  }) async {
    final now = DateTime.now();
    if (_connectInFlight) return;
    if (now.difference(_lastConnectTapAt) < const Duration(milliseconds: 800)) {
      return;
    }
    _lastConnectTapAt = now;
    if (overrideServer == null) {
      final serverError = kIsWeb
          ? webServerError(Uri.base, _serverController.text)
          : null;
      if (serverError != null) {
        setState(() {
          _editServer = true;
          _autoConnecting = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(serverError)));
        return;
      }
      if (!_formKey.currentState!.validate()) return;
    }
    if (overrideServer == null &&
        LoginAuthPolicy.requirePasswordBeforeConnect(
          mode: _mode,
          hasPassword: _hasPassword,
          tailscalePath: tailscalePath,
        )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the password or scan the QR code')),
      );
      return;
    }

    _connectInFlight = true;
    _connectAttempt += 1;
    final attempt = _connectAttempt;
    setState(() {
      _isLoading = true;
      _pairingCode = null;
    });
    if (saveServer) {
      await _saveCredentials();
    }
    if (overrideServer == null) {
      _closeBridge();
    }

    final target = overrideServer ?? _serverController.text;
    final password = passwordOverride ?? _passController.text;
    final pairIfNeeded = LoginAuthPolicy.pairIfNeeded(
      mode: _mode,
      hasPassword: password.isNotEmpty,
      tailscalePath: tailscalePath,
    );
    final snapshot = await CredentialStore.snapshot(server: target);
    if (!mounted || attempt != _connectAttempt) return;
    final proxy = StreamProxy(
      transportFactory: tailscalePath ? _tailscale.gameTransportFactory : null,
    );
    _inFlightProxy = proxy;
    try {
      await proxy
          .start(
            target,
            password,
            connectTimeout: Duration(seconds: tailscalePath ? 20 : 5),
            authTimeout: const Duration(minutes: 4),
            pairIfNeeded: pairIfNeeded,
            lookupPassword: snapshot.lookup,
            onBoundPassword: (keyId, secret) {
              if (_rememberCredentials) {
                unawaited(
                  CredentialStore.put(
                    keyId: keyId,
                    password: secret,
                    lastServer: target,
                  ),
                );
              }
              if (mounted) _passController.text = secret;
            },
            onPairingCode: (code) {
              if (!mounted) return;
              setState(() => _pairingCode = code);
            },
            onPairedPassword: (password) {
              unawaited(_persistPairedPassword(password));
            },
          )
          .timeout(const Duration(minutes: 4));

      if (attempt != _connectAttempt) {
        await proxy.stop();
        return;
      }

      if (kIsWeb) await CredentialStore.saveWebPreferTailscale(tailscalePath);
      if (kIsWeb && _rememberCredentials) {
        await CredentialStore.put(
          keyId: CredentialStore.legacyKeyId,
          password: _passController.text,
          lastServer: target,
        );
      }

      final worldState = await proxy.awaitWorldState(
        timeout: const Duration(seconds: 2),
      );
      if (attempt != _connectAttempt) {
        await proxy.stop();
        return;
      }

      if (mounted) {
        setState(() {
          _pairingCode = null;
          _passwordVisible = false;
        });
        final inWorld = worldState == null || worldState.isInWorld;
        final resolvedEndpoint = endpoint ?? DirectEndpoint(target);
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => inWorld
                ? StreamScreen(
                    proxy: proxy,
                    server: target,
                    password: _passController.text,
                    endpoint: resolvedEndpoint,
                  )
                : ServerPickerScreen(
                    proxy: proxy,
                    server: target,
                    password: _passController.text,
                    endpoint: resolvedEndpoint,
                  ),
          ),
        );
        if (mounted) await _loadCredentials();
      }
    } on PairingUnavailableException {
      await proxy.stop();
      if (attempt != _connectAttempt) return;
      if (mounted) {
        setState(() {
          _mode = LoginAuthMode.password;
          _pairingCode = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This address needs a password. Enter it or scan the QR code.',
            ),
          ),
        );
      }
    } on AuthFailureException catch (e) {
      await proxy.stop();
      if (attempt != _connectAttempt) return;
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        if (e.isInvalidSignature) {
          final keyId = e.keyId;
          if (keyId != null && keyId.isNotEmpty) {
            await CredentialStore.remove(keyId, server: target);
            if (kIsWeb) {
              await CredentialStore.remove(
                CredentialStore.legacyKeyId,
                server: target,
              );
            }
          } else {
            await CredentialStore.remove(
              CredentialStore.legacyKeyId,
              server: target,
            );
          }
          if (!mounted) return;
          _passController.clear();
          setState(() {
            _mode = LoginAuthMode.password;
            _pairingCode = null;
          });
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Saved password did not match this computer. Enter the current password or pair again.',
              ),
            ),
          );
        } else {
          messenger.showSnackBar(
            SnackBar(content: Text('Authentication failed: ${e.message}')),
          );
        }
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
        if (mounted) {
          setState(() {
            _isLoading = false;
            _autoConnecting = false;
            if (_pairingCode != null && !_connectInFlight) {
              _pairingCode = null;
            }
          });
        }
      }
    }
  }

  Future<void> _connectEmbeddedTailscale({bool autoSelectSaved = false}) async {
    if (_isLoading) return;
    try {
      final picked = await TailscaleLoginSheet.show(
        context,
        client: _tailscale,
        savedNodeId: _savedTailscaleNodeId,
        autoSelectSaved: autoSelectSaved,
      );
      if (picked == null || !mounted) return;
      await CredentialStore.saveRememberCredentials(_rememberCredentials);
      await CredentialStore.saveTailscaleNodeId(picked.nodeId);
      setState(() => _savedTailscaleNodeId = picked.nodeId);
      final lease = await _tailscale.openBridge(
        nodeId: picked.nodeId,
        port: picked.port,
      );
      _bridgeLeaseId = lease.leaseId;
      await _connect(
        overrideServer: lease.url,
        saveServer: false,
        tailscalePath: true,
        passwordOverride: '',
        endpoint: EmbeddedTailscaleEndpoint(
          client: _tailscale,
          nodeId: picked.nodeId,
          port: picked.port,
          leaseId: lease.leaseId,
          lastLoopbackUrl: lease.url,
        ),
      );
    } catch (e) {
      _closeBridge();
      if (!mounted) return;
      final detail = e is PlatformException
          ? [
              e.code,
              e.message,
            ].whereType<String>().where((s) => s.isNotEmpty).join(': ')
          : '$e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Built-in Tailscale failed: $detail')),
      );
    }
  }

  void _copyPassword() {
    final text = _passController.text;
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    _copiedPassword = text;
    _clipboardClearTimer?.cancel();
    _clipboardClearTimer = Timer(const Duration(seconds: 45), () async {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text == _copiedPassword) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
      _copiedPassword = null;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Password copied. Clipboard clears in 45 seconds.'),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clipboardClearTimer?.cancel();
    _serverController.removeListener(_onServerChanged);
    _passController.removeListener(_onPasswordChanged);
    _passwordFocus.removeListener(_onPasswordFocusChanged);
    _serverController.dispose();
    _passController.dispose();
    _passwordFocus.dispose();
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
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_platformCapabilities.isWeb &&
                        _tailscale.isSupported) ...[
                      FilledButton.icon(
                        onPressed: _isLoading
                            ? null
                            : _connectEmbeddedTailscale,
                        icon: const Icon(Icons.computer),
                        label: const Text('Connect with Tailscale'),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Sign in to find your game computer. No public server address needed.',
                      ),
                      const SizedBox(height: 24),
                      const Text('Or connect by address'),
                      const SizedBox(height: 8),
                    ],
                    if (kIsWeb && !_editServer)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Game computer'),
                        subtitle: Text(_serverController.text),
                        trailing: TextButton(
                          onPressed: _isLoading
                              ? null
                              : () => setState(() => _editServer = true),
                          child: const Text('Change'),
                        ),
                      )
                    else
                      TextFormField(
                        enabled: !kIsWeb || !_isLoading,
                        controller: _serverController,
                        decoration: InputDecoration(
                          labelText: 'Server address',
                          hintText: kIsWeb
                              ? 'wss://your-computer.tailnet.ts.net:9600'
                              : '192.168.0.3:9600 or example.ngrok-free.app',
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          return kIsWeb ? webServerError(Uri.base, v) : null;
                        },
                      ),
                    if (_autoConnecting)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('Connecting to your game…'),
                      ),
                    if (_showPasswordField && !_autoConnecting) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passController,
                        focusNode: _passwordFocus,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: () => setState(
                                  () => _passwordVisible = !_passwordVisible,
                                ),
                                icon: Icon(
                                  _passwordVisible
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                                tooltip: _passwordVisible
                                    ? 'Hide password'
                                    : 'Show password',
                              ),
                              IconButton(
                                onPressed: _passController.text.isEmpty
                                    ? null
                                    : _copyPassword,
                                icon: const Icon(Icons.copy),
                                tooltip: 'Copy password',
                              ),
                              if (_platformCapabilities.supportsQrScanner)
                                IconButton(
                                  onPressed: _isLoading ? null : _scanPassword,
                                  icon: const Icon(Icons.qr_code_scanner),
                                  tooltip: 'Scan QR code',
                                ),
                            ],
                          ),
                          suffixIconConstraints: const BoxConstraints(
                            minWidth: 0,
                            minHeight: 0,
                          ),
                        ),
                        obscureText: !_passwordVisible,
                      ),
                      if (!_hasPassword) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: _isLoading
                                ? null
                                : () => setState(
                                    () => _mode = LoginAuthMode.pair,
                                  ),
                            child: const Text(
                              'Pair instead (same Wi-Fi or Tailscale)',
                            ),
                          ),
                        ),
                      ],
                    ] else if (!_hasPassword) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: _isLoading
                              ? null
                              : () => setState(
                                  () => _mode = LoginAuthMode.password,
                                ),
                          child: const Text('Use password or scan QR'),
                        ),
                      ),
                    ],
                    if (!_autoConnecting)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _rememberCredentials,
                        onChanged: _isLoading
                            ? null
                            : (value) {
                                setState(
                                  () => _rememberCredentials = value ?? true,
                                );
                              },
                        title: const Text(
                          kIsWeb
                              ? 'Remember and connect automatically'
                              : 'Remember password on this phone',
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    if (_pairingCode != null) ...[
                      const SizedBox(height: 8),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                kIsWeb
                                    ? 'On the computer, allow this browser'
                                    : 'On the computer, Allow this phone',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Or run /monkey accept ${_pairingCode!.displayCode}',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (_platformCapabilities.isAndroid)
                      Row(
                        children: [
                          Expanded(
                            child: _connectButton(
                              expanded: false,
                              onPressed: _isLoading
                                  ? _cancelConnect
                                  : () => _connect(),
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
                    else
                      _connectButton(
                        expanded: isPortrait,
                        onPressed: _isLoading
                            ? _cancelConnect
                            : () => _connect(),
                      ),
                    if (_platformCapabilities.isIOS ||
                        _platformCapabilities.isAndroid) ...[
                      const SizedBox(height: 24),
                      const Divider(),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _isLoading
                            ? null
                            : _connectEmbeddedTailscale,
                        child: const Text('Connect with Tailscale'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
