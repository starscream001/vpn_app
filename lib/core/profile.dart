import 'dart:convert';
import 'package:crypto/crypto.dart';

enum Protocol { auto, vless, amnezia }

class Profile {
  const Profile({
    required this.id,
    required this.name,
    required this.protocol,
    required this.config,
    this.revision = 1,
    this.source = 'local',
    this.expiresAt,
    this.revoked = false,
    this.lastSuccess,
    this.latency,
  });
  final String id, name, config, source;
  final Protocol protocol;
  final int revision;
  final DateTime? expiresAt, lastSuccess;
  final bool revoked;
  final int? latency;
  bool usable(DateTime now) =>
      !revoked && (expiresAt == null || expiresAt!.isAfter(now));
  Profile success(int ms) => Profile(
    id: id,
    name: name,
    protocol: protocol,
    config: config,
    revision: revision,
    source: source,
    expiresAt: expiresAt,
    revoked: revoked,
    lastSuccess: DateTime.now().toUtc(),
    latency: ms,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'protocol': protocol.name,
    'config': config,
    'revision': revision,
    'source': source,
    'expiresAt': expiresAt?.toIso8601String(),
    'revoked': revoked,
    'lastSuccess': lastSuccess?.toIso8601String(),
    'latency': latency,
  };
  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
    id: j['id'] as String,
    name: j['name'] as String,
    protocol: Protocol.values.byName(j['protocol'] as String),
    config: j['config'] as String,
    revision: j['revision'] as int? ?? 1,
    source: j['source'] as String? ?? 'local',
    revoked: j['revoked'] == true,
    expiresAt: DateTime.tryParse(j['expiresAt'] as String? ?? ''),
    lastSuccess: DateTime.tryParse(j['lastSuccess'] as String? ?? ''),
    latency: j['latency'] as int?,
  );
}

String configId(String text) => sha256.convert(utf8.encode(text)).toString();

List<Profile> parseProfiles(String input, {String source = 'local'}) {
  if (utf8.encode(input).length > 1024 * 1024) {
    throw const FormatException('Файл больше 1 МБ');
  }
  var text = input.trim();
  if (!text.startsWith('vless://') && !text.startsWith('[Interface]')) {
    try {
      text = utf8.decode(base64.decode(base64.normalize(text))).trim();
    } catch (_) {}
  }
  if (text.startsWith('[Interface]')) {
    if (RegExp(
      r'^\s*(PreUp|PostUp|PreDown|PostDown|IncludedApplications|ExcludedApplications)\s*=',
      multiLine: true,
      caseSensitive: false,
    ).hasMatch(text)) {
      throw const FormatException(
        'Команды и правила приложений в импортируемом профиле запрещены',
      );
    }
    for (final field in [
      'PrivateKey',
      'Address',
      'PublicKey',
      'Endpoint',
      'AllowedIPs',
    ]) {
      if (!RegExp(
        '^\\s*$field\\s*=\\s*\\S+',
        multiLine: true,
        caseSensitive: false,
      ).hasMatch(text)) {
        throw FormatException('В профиле нет $field');
      }
    }
    return [
      Profile(
        id: configId(text),
        name: 'AmneziaWG',
        protocol: Protocol.amnezia,
        config: text,
        source: source,
      ),
    ];
  }
  final result = <Profile>[];
  for (final line
      in const LineSplitter().convert(text).where((l) => l.trim().isNotEmpty)) {
    final uri = Uri.tryParse(line.trim());
    if (uri == null ||
        uri.scheme != 'vless' ||
        uri.host.isEmpty ||
        !uri.hasPort ||
        uri.port < 1 ||
        uri.port > 65535 ||
        !RegExp(
          r'^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$',
        ).hasMatch(uri.userInfo)) {
      throw const FormatException(
        'Нужна ссылка VLESS или конфигурация AmneziaWG .conf',
      );
    }
    final q = uri.queryParameters;
    if (!['tcp', 'raw'].contains(q['type'] ?? 'tcp') ||
        !['reality', 'tls'].contains(q['security'])) {
      throw const FormatException('Поддерживается VLESS TCP с Reality или TLS');
    }
    if (q['security'] == 'reality' &&
        ((q['pbk'] ?? '').isEmpty || (q['sni'] ?? '').isEmpty)) {
      throw const FormatException('Reality требует public key и SNI');
    }
    if ((q['allowInsecure'] ?? '0') != '0') {
      throw const FormatException('Небезопасный TLS запрещён');
    }
    result.add(
      Profile(
        id: configId(line.trim()),
        name: uri.fragment.isEmpty ? uri.host : uri.fragment,
        protocol: Protocol.vless,
        config: line.trim(),
        source: source,
      ),
    );
  }
  if (result.isEmpty) throw const FormatException('Нет профилей');
  return {for (final p in result) p.id: p}.values.toList();
}

/// Partial refreshes never erase missing profiles. Explicit revocation and expiry win.
List<Profile> mergeCatalog(
  List<Profile> old,
  List<Profile> incoming, {
  Set<String> revokedIds = const {},
  required DateTime now,
}) {
  final merged = {for (final p in old) p.id: p};
  for (final p in incoming) {
    final previous = merged[p.id];
    if (previous == null || p.revision > previous.revision || p.revoked) {
      merged[p.id] = p;
    }
  }
  merged.removeWhere((id, p) => revokedIds.contains(id) || !p.usable(now));
  return merged.values.toList();
}

List<Profile> rankProfiles(
  List<Profile> profiles,
  Protocol mode,
  DateTime now,
) {
  final eligible = profiles
      .where(
        (p) => p.usable(now) && (mode == Protocol.auto || p.protocol == mode),
      )
      .toList();
  eligible.sort((a, b) {
    if (a.lastSuccess != null && b.lastSuccess == null) return -1;
    if (b.lastSuccess != null && a.lastSuccess == null) return 1;
    return (a.latency ?? (a.protocol == Protocol.amnezia ? 10000 : 20000))
        .compareTo(
          b.latency ?? (b.protocol == Protocol.amnezia ? 10000 : 20000),
        );
  });
  return eligible;
}
