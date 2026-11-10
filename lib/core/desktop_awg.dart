import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'engine.dart';
import 'profile.dart';
import 'routing.dart';

class WindowsAwgEngine implements TunnelEngine {
  String get helper =>
      '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}foxway-awg.exe';
  Future<String> _command(String command, {String? input}) async {
    if (!await File(helper).exists()) {
      throw StateError('В архиве нет AWG helper');
    }
    final p = await Process.start(helper, [command], runInShell: false);
    final out = p.stdout.transform(utf8.decoder).join();
    unawaited(p.stderr.drain<void>());
    if (input != null) p.stdin.write(input);
    await p.stdin.close();
    try {
      final code = await p.exitCode.timeout(const Duration(seconds: 25));
      if (code != 0) {
        throw StateError(
          'Windows AWG: нужны права администратора или корректный профиль',
        );
      }
      return await out;
    } finally {
      p.kill();
    }
  }

  @override
  Future<void> start(Profile p, RoutingPolicy policy) async {
    if (policy.domains.isNotEmpty || policy.excludedApps.isNotEmpty) {
      throw UnsupportedError(
        'AWG desktop: доменные и app-исключения ещё не поддержаны',
      );
    }
    await _command('up', input: p.config);
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      if ((await traffic()).up) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    await stop();
    throw TimeoutException('AWG service не запустился');
  }

  @override
  Future<void> stop() async {
    await _command('down');
  }

  @override
  Future<Traffic> traffic() async {
    try {
      final j = jsonDecode(await _command('stats')) as Map;
      return Traffic(
        (j['rx'] as num).toInt(),
        (j['tx'] as num).toInt(),
        j['up'] == true,
      );
    } catch (_) {
      return const Traffic(0, 0, false);
    }
  }
}

/// Also used by macOS: AWG has its own NE provider and no second Go runtime in libbox.
class AppleAwgOnlyEngine implements TunnelEngine {
  static const channel = MethodChannel('app.foxway/apple-awg');
  @override
  Future<void> start(Profile p, RoutingPolicy policy) async {
    if (policy.domains.isNotEmpty || policy.excludedApps.isNotEmpty) {
      throw UnsupportedError(
        'AWG Apple: доменные и app-исключения ещё не поддержаны',
      );
    }
    await channel.invokeMethod<void>('start', {'config': p.config});
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      if ((await traffic()).up) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    await stop();
    throw TimeoutException('AWG extension не запустился; проверьте подпись');
  }

  @override
  Future<void> stop() => channel.invokeMethod<void>('stop');
  @override
  Future<Traffic> traffic() async {
    final s = await channel.invokeMapMethod<String, dynamic>('stats') ?? {};
    return Traffic(
      (s['rx'] as num? ?? 0).toInt(),
      (s['tx'] as num? ?? 0).toInt(),
      s['up'] == true,
    );
  }
}

class LinuxAwgEngine implements TunnelEngine {
  String? _interface;
  String? _config;
  Future<void> _invoke(String action, String raw) async {
    final folder = File(Platform.resolvedExecutable).parent.path;
    final script = '$folder/awg-quick';
    if (!await File(script).exists()) {
      throw StateError('В архиве нет AWG tools');
    }
    final uid = await Process.run('/usr/bin/id', ['-u']);
    if (uid.exitCode != 0) {
      throw StateError('Не удалось определить владельца туннеля');
    }
    _interface =
        'fw${configId('foxway:${uid.stdout.toString().trim()}').substring(0, 10)}';
    final root = uid.stdout.toString().trim() == '0';
    final p = await Process.start(root ? '/bin/bash' : '/usr/bin/pkexec', [
      if (!root) '/bin/bash',
      script,
      action,
      'stdin:$_interface',
    ], runInShell: false);
    unawaited(p.stdout.drain<void>());
    unawaited(p.stderr.drain<void>());
    p.stdin.write(raw);
    await p.stdin.close();
    // Wait for the system authorization dialog; timing it out could start a stale tunnel later.
    if (await p.exitCode != 0) {
      throw StateError(
        'AWG: проверьте разрешение администратора, iproute2 и resolvconf',
      );
    }
  }

  @override
  Future<void> start(Profile p, RoutingPolicy policy) async {
    if (policy.domains.isNotEmpty || policy.excludedApps.isNotEmpty) {
      throw UnsupportedError(
        'AWG Linux: доменные и app-исключения ещё не поддержаны',
      );
    }
    await _invoke('up', p.config);
    _config = p.config;
  }

  @override
  Future<void> stop() async {
    final raw = _config;
    if (raw == null) return;
    await _invoke('down', raw);
    _config = null;
    _interface = null;
  }

  @override
  Future<Traffic> traffic() async {
    if (_config == null || _interface == null) {
      return const Traffic(0, 0, false);
    }
    try {
      final base = '/sys/class/net/$_interface/statistics';
      return Traffic(
        int.parse((await File('$base/rx_bytes').readAsString()).trim()),
        int.parse((await File('$base/tx_bytes').readAsString()).trim()),
        true,
      );
    } catch (_) {
      return const Traffic(0, 0, false);
    }
  }
}
