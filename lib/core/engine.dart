import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import 'profile.dart';
import 'routing.dart';

class Traffic {
  const Traffic(this.rx, this.tx, this.up);
  final int rx, tx;
  final bool up;
}

abstract interface class TunnelEngine {
  Future<void> start(Profile profile, RoutingPolicy policy);
  Future<void> stop();
  Future<Traffic> traffic();
}

abstract interface class ProxyProbeEngine {
  String? get httpProxy;
}

class AndroidEngine implements TunnelEngine, ProxyProbeEngine {
  @override
  String? get httpProxy =>
      _active?.protocol == Protocol.vless ? "PROXY 127.0.0.1:10809" : null;
  static const channel = MethodChannel('app.foxway/tunnel');
  Profile? _active;
  bool _initialized = false;
  V2RayStatus _status = V2RayStatus();
  late final FlutterV2ray _xray = FlutterV2ray(
    onStatusChanged: (s) => _status = s,
  );
  @override
  Future<void> start(Profile profile, RoutingPolicy policy) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'VPN пока подключён только на Android. Эта платформа — предварительная сборка.',
      );
    }
    await stop();
    if (profile.protocol == Protocol.amnezia) {
      if (policy.domains.isNotEmpty) {
        throw UnsupportedError(
          'Доменные исключения пока доступны только для VLESS',
        );
      }
      await channel.invokeMethod('start', {
        'config': profile.config,
        'excludedApps': policy.excludedApps,
      });
    } else {
      if (!_initialized) {
        await _xray.initializeV2Ray();
        _initialized = true;
      }
      if (!await _xray.requestPermission()) {
        throw StateError('Разрешение VPN не выдано');
      }
      _status = V2RayStatus();
      await _xray.startV2Ray(
        remark: 'FoxWay VPN',
        config: xrayConfig(profile.config, policy),
        blockedApps: policy.excludedApps,
        bypassSubnets: ['0.0.0.0/0', '::/0'],
      );
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (_status.state != 'CONNECTED') {
        if (DateTime.now().isAfter(deadline)) {
          await _xray.stopV2Ray();
          throw TimeoutException('Туннель не запустился');
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    _active = profile;
  }

  @override
  Future<Traffic> traffic() async {
    if (_active?.protocol == Protocol.amnezia) {
      final j = await channel.invokeMapMethod<String, dynamic>('stats') ?? {};
      return Traffic(
        j['rx'] as int? ?? 0,
        j['tx'] as int? ?? 0,
        j['up'] == true,
      );
    }
    return Traffic(
      _status.download,
      _status.upload,
      _status.state == 'CONNECTED',
    );
  }

  @override
  Future<void> stop() async {
    if (!Platform.isAndroid) return;
    // Stop both: process recreation can lose the Dart-side active profile.
    await channel.invokeMethod('stop');
    if (_initialized) await _xray.stopV2Ray();
    _active = null;
  }
}

class ProbeResult {
  const ProbeResult(this.ok, this.ms, this.rx, this.tx, this.reason);
  final bool ok;
  final int ms, rx, tx;
  final String reason;
}

abstract interface class QualityProbe {
  Future<ProbeResult> check(TunnelEngine engine);
}

class HttpsProbe implements QualityProbe {
  HttpsProbe(this.url);
  final Uri url;
  @override
  Future<ProbeResult> check(TunnelEngine engine) async {
    final before = await engine.traffic();
    final sw = Stopwatch()..start();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    final proxy = engine is ProxyProbeEngine
        ? (engine as ProxyProbeEngine).httpProxy
        : null;
    if (proxy != null) {
      client.findProxy = (_) => proxy;
    }
    try {
      if (url.scheme != 'https') throw StateError('HTTPS required');
      if (!before.up) return const ProbeResult(false, 0, 0, 0, 'tunnel_down');
      final req = await client.getUrl(url).timeout(const Duration(seconds: 10));
      req.followRedirects = false;
      req.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final res = await req.close().timeout(const Duration(seconds: 10));
      var received = 0;
      await for (final chunk in res.timeout(const Duration(seconds: 10))) {
        received += chunk.length;
        if (received > 65536) break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      final after = await engine.traffic();
      final rx = after.rx - before.rx, tx = after.tx - before.tx;
      final ok = res.statusCode == 204 && after.up && rx > 0 && tx > 0;
      return ProbeResult(
        ok,
        sw.elapsedMilliseconds,
        rx < 0 ? 0 : rx,
        tx < 0 ? 0 : tx,
        ok ? 'https_204' : 'route_or_response_failed',
      );
    } catch (_) {
      return ProbeResult(false, sw.elapsedMilliseconds, 0, 0, 'https_failed');
    } finally {
      client.close(force: true);
    }
  }
}
