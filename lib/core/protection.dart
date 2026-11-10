import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'engine.dart';
import 'profile.dart';
import 'routing.dart';

abstract interface class ProtectionControl {
  Future<void> prepareProtection(List<Profile> profiles);
  Future<void> releaseProtection();
}

class NativeGuard {
  final Future<ProcessResult> Function(String, List<String>, {String? input})?
  runner;
  NativeGuard({this.runner});
  Future<ProcessResult> _run(
    String file,
    List<String> args, {
    String? input,
  }) async {
    if (runner != null) return runner!(file, args, input: input);
    final p = await Process.start(file, args, runInShell: false);
    final out = p.stdout.transform(utf8.decoder).join();
    final err = p.stderr.transform(utf8.decoder).join();
    if (input != null) p.stdin.write(input);
    await p.stdin.close();
    final code = await p.exitCode;
    return ProcessResult(p.pid, code, await out, await err);
  }

  Future<void> _checked(String file, List<String> args, {String? input}) async {
    if ((await _run(file, args, input: input)).exitCode != 0) {
      throw UnsupportedError(
        'Не удалось настроить защиту. Нужны права администратора и системный firewall.',
      );
    }
  }

  Future<String> linuxInterface() async {
    final uid = await Process.run('/usr/bin/id', ['-u']);
    if (uid.exitCode != 0) {
      throw StateError('Не удалось определить пользователя');
    }
    return 'fw${configId('foxway:${uid.stdout.toString().trim()}').substring(0, 10)}';
  }

  Future<void> _linux(String action, {String? interface}) async {
    final script =
        '${File(Platform.resolvedExecutable).parent.path}/foxway-guard.py';
    final uid = await Process.run('/usr/bin/id', ['-u']);
    final root = uid.stdout.toString().trim() == '0';
    await _checked(root ? '/usr/bin/python3' : '/usr/bin/pkexec', [
      if (!root) '/usr/bin/python3',
      script,
      action,
    ], input: jsonEncode({'interface': interface}));
  }

  Future<void> _windows(String action, {Protocol? protocol}) async => _checked(
    '${File(Platform.resolvedExecutable).parent.path}\\foxway-awg.exe',
    [action],
    input: protocol == null ? null : jsonEncode({'protocol': protocol.name}),
  );
  Future<void> arm(Profile p) async {
    if (Platform.isWindows) {
      await _windows('guard-arm');
      return;
    }
    if (Platform.isLinux) {
      await _linux(
        'arm',
        interface: p.protocol == Protocol.vless
            ? 'fwvless0'
            : await linuxInterface(),
      );
      return;
    }
    if (Platform.isMacOS && p.protocol == Protocol.vless) {
      final rules = await _run('/sbin/pfctl', ['-sr']);
      if (rules.exitCode != 0 ||
          !rules.stdout.toString().contains('anchor "com.apple/*"')) {
        throw StateError(
          'В системном PF нет Apple anchor; требуется отдельная настройка администратора',
        );
      }
      final endpoint = Uri.parse(p.config);
      final address = InternetAddress.tryParse(endpoint.host);
      if (address == null) {
        throw StateError('Защита требует разрешённый IP сервера');
      }
      final body =
          'pass quick on lo0 all\npass out quick on utun88 all keep state (if-bound)\npass out quick proto tcp to ${address.address} port ${endpoint.port} keep state (if-bound)\npass out quick proto udp from any port 68 to any port 67\npass out quick inet6 proto icmp6 icmp6-type { 133, 134, 135, 136 }\nblock drop out quick all\n';
      await _checked('/sbin/pfctl', [
        '-a',
        'com.apple/foxway',
        '-f',
        '-',
      ], input: body);
      final tokenFile = File('/var/run/foxway-pf.token');
      if (!await tokenFile.exists()) {
        final enabled = await _run('/sbin/pfctl', ['-E']);
        final token = RegExp(
          r'Token\s*:\s*(\d+)',
        ).firstMatch('${enabled.stdout}\n${enabled.stderr}');
        if (enabled.exitCode != 0 || token == null) {
          throw StateError('Не удалось включить PF');
        }
        await tokenFile.writeAsString(token[1]!);
        await _checked('/bin/chmod', ['600', tokenFile.path]);
      }
      // A floating PF state from before activation could otherwise bypass the new rules.
      // The strict-mode consent explains that existing network connections will close.
      // This clears connection states, never the main ruleset or somebody else's rules.
      await _checked('/sbin/pfctl', ['-F', 'states']);
    }
  }

  Future<void> bind(Profile p) async {
    if (Platform.isWindows) await _windows('guard-bind', protocol: p.protocol);
  }

  Future<void> off() async {
    if (Platform.isWindows) {
      await _windows('guard-off');
      return;
    }
    if (Platform.isLinux) {
      await _linux('off');
      return;
    }
    if (Platform.isMacOS) {
      // Empty only FoxWay's anchor. Never disable or flush the system PF ruleset.
      await _checked('/sbin/pfctl', [
        '-a',
        'com.apple/foxway',
        '-f',
        '-',
      ], input: '');
      final file = File('/var/run/foxway-pf.token');
      if (await file.exists()) {
        final token = (await file.readAsString()).trim();
        if (!RegExp(r'^\d+$').hasMatch(token)) {
          throw StateError('Неверный PF token');
        }
        await _checked('/sbin/pfctl', ['-X', token]);
        await file.delete();
      }
    }
  }
}

/// Stops/failover never remove the desktop firewall. Only an explicit user release does.
class ProtectedEngine
    implements TunnelEngine, ProxyProbeEngine, ProtectionControl {
  ProtectedEngine(this.inner, {NativeGuard? guard})
    : guard = guard ?? NativeGuard();
  final TunnelEngine inner;
  final NativeGuard guard;
  bool armed = false;
  bool _appleHold = false;
  bool _firewall = false;
  String? _heldId;
  final Map<String, Profile> _pinned = {};
  @override
  String? get httpProxy =>
      inner is ProxyProbeEngine ? (inner as ProxyProbeEngine).httpProxy : null;
  Future<Profile> _pin(Profile p) async {
    if (_pinned.containsKey(p.config)) return _pinned[p.config]!;
    Future<String> address(String host) async {
      final ip = InternetAddress.tryParse(host);
      return ip?.address ?? (await InternetAddress.lookup(host)).first.address;
    }

    var config = p.config;
    if (p.protocol == Protocol.vless) {
      final u = Uri.parse(config);
      final ip = await address(u.host);
      config = u
          .replace(
            host: ip,
            queryParameters: {
              ...u.queryParameters,
              'sni': u.queryParameters['sni'] ?? u.host,
            },
          )
          .toString();
    } else {
      final matches = RegExp(
        r'^\s*Endpoint\s*=\s*(\S+)\s*$',
        multiLine: true,
        caseSensitive: false,
      ).allMatches(config).toList();
      for (final m in matches.reversed) {
        final u = Uri.parse('udp://${m[1]}');
        final ip = await address(u.host);
        config = config.replaceRange(
          m.start,
          m.end,
          'Endpoint = ${ip.contains(':') ? '[$ip]' : ip}:${u.port}',
        );
      }
      if (Platform.isLinux) {
        config = config.replaceAll(
          RegExp(r'^\s*FwMark\s*=.*$', multiLine: true, caseSensitive: false),
          '',
        );
        config = config.replaceFirst(
          '[Interface]',
          '[Interface]\nFwMark = 0x4657',
        );
      }
    }
    return _pinned[p.config] = Profile.fromJson({
      ...p.toJson(),
      'config': config,
    });
  }

  @override
  Future<void> prepareProtection(List<Profile> profiles) async {
    // Resolve all bounded candidates before the firewall is first armed.
    if (armed || Platform.isAndroid || Platform.isIOS) return;
    for (final p in profiles) {
      try {
        await _pin(p);
      } catch (_) {
        /* Start fails closed if this endpoint remains unresolved. */
      }
    }
  }

  @override
  Future<void> start(Profile p, RoutingPolicy policy) async {
    if (!policy.killSwitch) {
      await inner.start(p, policy);
      return;
    }
    if (_appleHold && _heldId == p.id) return;
    if (_appleHold && _heldId != p.id) {
      throw UnsupportedError(
        'Строгая защита Apple удерживает текущий сервер. Отключите VPN явно перед сменой.',
      );
    }
    final nativeApple =
        Platform.isIOS || (Platform.isMacOS && p.protocol == Protocol.amnezia);
    final profile = Platform.isAndroid || nativeApple ? p : await _pin(p);
    if (!Platform.isAndroid && !nativeApple) {
      _firewall = true;
      await guard.arm(profile);
    }
    armed = true;
    _appleHold = nativeApple;
    _heldId = p.id;
    await inner.start(profile, policy);
    if (!Platform.isAndroid && !nativeApple) await guard.bind(profile);
  }

  @override
  Future<void> stop() async {
    if (!_appleHold) await inner.stop();
  }

  @override
  Future<void> releaseProtection() async {
    // Stop the owned tunnel first. A failed firewall removal remains visible to the caller.
    await inner.stop();
    if (Platform.isAndroid) {
      await const MethodChannel(
        'app.foxway/tunnel',
      ).invokeMethod<void>('settings');
    }
    if (Platform.isWindows ||
        Platform.isLinux ||
        (Platform.isMacOS &&
            (_firewall || await File('/var/run/foxway-pf.token').exists()))) {
      await guard.off();
    }
    armed = false;
    _firewall = false;
    _appleHold = false;
    _heldId = null;
    _pinned.clear();
  }

  @override
  Future<Traffic> traffic() => inner.traffic();
}
