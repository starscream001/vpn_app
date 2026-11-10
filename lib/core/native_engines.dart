import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:sing_box/sing_box.dart';
import 'package:sing_box/sing_box_platform_interface.dart';
import 'engine.dart';
import 'profile.dart';
import 'routing.dart';
import 'sing_config.dart';

TunnelEngine platformEngine() => Platform.isAndroid
    ? AndroidEngine()
    : Platform.isIOS
    ? AppleTunnelEngine()
    : DesktopTunnelEngine();

class AppleTunnelEngine implements TunnelEngine {
  final _native = SingBoxPlatform.instance;
  bool _initialized = false;
  SingBoxConnectionStatus _state = SingBoxConnectionStatus.disconnected;
  SingBoxConnectionStats _stats = SingBoxConnectionStats.empty;
  StreamSubscription<SingBoxConnectionState>? _states;
  StreamSubscription<SingBoxConnectionStats>? _counters;
  Future<void> _init() async {
    if (_initialized) return;
    final info = await _native.initialize(
      const SingBoxOptions(
        logMaxLines: 0,
        ios: SingBoxIosOptions(
          appGroup: 'group.app.foxway.foxway',
          tunnelBundleIdentifier: 'app.foxway.foxway.PacketTunnel',
          profileName: 'FoxWay VPN',
        ),
      ),
    );
    _state = info.status;
    _states = _native.watchState().listen((s) => _state = s.status);
    _counters = _native.watchStats().listen((s) => _stats = s);
    _initialized = true;
  }

  @override
  Future<void> start(Profile profile, RoutingPolicy policy) async {
    final config = singConfig(profile, policy);
    await _init();
    if (!await _native.requestVpnPermission()) {
      throw StateError('Разрешение VPN не выдано');
    }
    await _native.start(config);
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (_state != SingBoxConnectionStatus.connected) {
      if (DateTime.now().isAfter(deadline)) {
        await _native.stop();
        throw TimeoutException('iOS VPN не запустился');
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  @override
  Future<Traffic> traffic() async => Traffic(
    _stats.downloadTotal,
    _stats.uploadTotal,
    _state == SingBoxConnectionStatus.connected,
  );
  @override
  Future<void> stop() async {
    await _init();
    await _native.stop();
  }

  Future<void> dispose() async {
    await _states?.cancel();
    await _counters?.cancel();
  }
}

/// Owns one native TUN process. Secrets travel through stdin, never command arguments/files.
class DesktopTunnelEngine implements TunnelEngine, ProxyProbeEngine {
  Process? _process;
  int _apiPort = 0, _probePort = 0;
  String _secret = '';
  bool _up = false;
  @override
  String? get httpProxy => _up ? 'PROXY 127.0.0.1:$_probePort' : null;
  Future<int> _port() async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final p = s.port;
    await s.close();
    return p;
  }

  @override
  Future<void> start(Profile profile, RoutingPolicy policy) async {
    if (profile.protocol != Protocol.vless) {
      throw UnsupportedError('Desktop: пока доступен VLESS/Reality');
    }
    await stop();
    _apiPort = await _port();
    _probePort = await _port();
    _secret = List.generate(
      32,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final folder = File(Platform.resolvedExecutable).parent.path;
    final binary =
        Platform.environment['FOXWAY_SING_BOX_BINARY'] ??
        '$folder${Platform.pathSeparator}sing-box${Platform.isWindows ? '.exe' : ''}';
    if (!await File(binary).exists()) {
      throw StateError(
        'В сборке нет sing-box. Переустановите полный desktop архив.',
      );
    }
    final config = singConfig(
      profile,
      policy,
      desktop: true,
      probePort: _probePort,
      apiPort: _apiPort,
      secret: _secret,
    );
    final process = await Process.start(binary, [
      'run',
      '-c',
      'stdin',
    ], runInShell: false);
    _process = process;
    // Discard native diagnostics: configuration errors can contain credentials.
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    unawaited(
      process.exitCode.then((_) {
        if (identical(_process, process)) _up = false;
      }),
    );
    process.stdin.write(config);
    await process.stdin.close();
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      try {
        await _snapshot();
        _up = true;
        return;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    await stop();
    throw StateError(
      'TUN не запустился. Требуются права на создание VPN-интерфейса; смотрите инструкцию desktop.',
    );
  }

  Future<Map<String, dynamic>> _snapshot() async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    try {
      final req = await c
          .getUrl(Uri.parse('http://127.0.0.1:$_apiPort/connections'))
          .timeout(const Duration(seconds: 1));
      req.headers.set('Authorization', 'Bearer $_secret');
      final res = await req.close().timeout(const Duration(seconds: 1));
      if (res.statusCode != 200) throw StateError('Core not ready');
      return jsonDecode(
            await utf8.decoder
                .bind(res)
                .join()
                .timeout(const Duration(seconds: 1)),
          )
          as Map<String, dynamic>;
    } finally {
      c.close(force: true);
    }
  }

  @override
  Future<Traffic> traffic() async {
    if (!_up) return const Traffic(0, 0, false);
    try {
      final s = await _snapshot();
      return Traffic(
        (s['downloadTotal'] as num).toInt(),
        (s['uploadTotal'] as num).toInt(),
        _up,
      );
    } catch (_) {
      return const Traffic(0, 0, false);
    }
  }

  @override
  Future<void> stop() async {
    final p = _process;
    _process = null;
    _up = false;
    if (p == null) return;
    p.kill();
    try {
      await p.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      p.kill(ProcessSignal.sigkill);
      await p.exitCode;
    }
  }
}
