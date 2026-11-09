import 'dart:convert';
import 'dart:io';
import 'profile.dart';

Uri requireHttps(String input) {
  final u = Uri.parse(input);
  if (u.scheme != 'https' ||
      u.host.isEmpty ||
      u.userInfo.isNotEmpty ||
      u.hasFragment) {
    throw const FormatException('Нужен HTTPS-адрес без логина и пароля');
  }
  return u;
}

class ApiClient {
  ApiClient(this.base, {this.token});
  final Uri base;
  final String? token;
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    requireHttps(base.toString());
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client
          .openUrl(body == null ? 'GET' : 'POST', base.resolve(path))
          .timeout(const Duration(seconds: 15));
      req.followRedirects = false;
      req.headers.contentType = ContentType.json;
      if (token != null) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (body != null) req.write(jsonEncode(body));
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw HttpException('API: ${res.statusCode}');
      }
      var bytes = 0;
      final chunks = <int>[];
      await for (final chunk in res.timeout(const Duration(seconds: 15))) {
        bytes += chunk.length;
        if (bytes > 1024 * 1024) {
          throw const FormatException('Ответ API слишком большой');
        }
        chunks.addAll(chunk);
      }
      return chunks.isEmpty
          ? {}
          : jsonDecode(utf8.decode(chunks)) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }
}

Future<List<Profile>> downloadSubscription(String url) async {
  final uri = requireHttps(url);
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.getUrl(uri).timeout(const Duration(seconds: 15));
    req.followRedirects = false;
    final res = await req.close().timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw HttpException('Подписка: ${res.statusCode}');
    }
    final bytes = <int>[];
    await for (final chunk in res.timeout(const Duration(seconds: 15))) {
      bytes.addAll(chunk);
      if (bytes.length > 1024 * 1024) {
        throw const FormatException('Подписка больше 1 МБ');
      }
    }
    return parseProfiles(utf8.decode(bytes), source: configId(url));
  } finally {
    client.close(force: true);
  }
}

class QualityReport {
  QualityReport({
    required this.profileId,
    required this.protocol,
    required this.ok,
    required this.latencyMs,
    required this.rxDelta,
    required this.txDelta,
    required this.reason,
    DateTime? at,
  }) : at = at ?? DateTime.now().toUtc();
  final String profileId, protocol, reason;
  final bool ok;
  final int latencyMs, rxDelta, txDelta;
  final DateTime at;
  // No config, hostname, IP, application list, key, URL or browsing data.
  Map<String, dynamic> toJson() => {
    'profile_id': profileId,
    'protocol': protocol,
    'ok': ok,
    'latency_ms': latencyMs,
    'rx_delta': rxDelta,
    'tx_delta': txDelta,
    'reason': reason,
    'at': at.toIso8601String(),
  };
}

class ReportQueue {
  ReportQueue({
    required this.persist,
    required this.send,
    List<Map<String, dynamic>>? pending,
  }) : pending = pending ?? [];
  final Future<void> Function() persist;
  final Future<void> Function(List<Map<String, dynamic>>) send;
  final List<Map<String, dynamic>> pending;
  bool _sending = false;
  Future<void> add(QualityReport report) async {
    pending.add(report.toJson());
    if (pending.length > 100) pending.removeAt(0);
    await persist();
  }

  Future<void> flush() async {
    if (_sending || pending.isEmpty) return;
    _sending = true;
    final batch = List<Map<String, dynamic>>.from(pending.take(20));
    try {
      await send(batch);
      pending.removeRange(0, batch.length);
      await persist();
    } catch (_) {
      /* Keep encrypted pending events; next scheduled attempt retries. */
    } finally {
      _sending = false;
    }
  }
}
