import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

const appVersion = '0.3.1-preview.1';
const releaseRepository = 'starscream001/vpn_app';

/// Semver comparison includes numeric prerelease precedence and ignores build metadata.
int compareVersions(String a, String b) {
  List<String> parts(String s) =>
      s.replaceFirst(RegExp(r'^v'), '').split('+').first.split('-');
  final x = parts(a), y = parts(b);
  final xn = x.first.split('.'), yn = y.first.split('.');
  if (xn.length != 3 || yn.length != 3) {
    throw const FormatException('Invalid version');
  }
  for (var i = 0; i < 3; i++) {
    final c = int.parse(xn[i]).compareTo(int.parse(yn[i]));
    if (c != 0) return c;
  }
  if (x.length == 1 || y.length == 1) {
    return x.length == y.length ? 0 : (x.length == 1 ? 1 : -1);
  }
  final xp = x.skip(1).join('-').split('.'),
      yp = y.skip(1).join('-').split('.');
  for (var i = 0; i < xp.length && i < yp.length; i++) {
    final n = int.tryParse(xp[i]), m = int.tryParse(yp[i]);
    final c = n != null && m != null
        ? n.compareTo(m)
        : n != null
        ? -1
        : m != null
        ? 1
        : xp[i].compareTo(yp[i]);
    if (c != 0) return c;
  }
  return xp.length.compareTo(yp.length);
}

Uri trustedReleaseUrl(String input) {
  final u = Uri.parse(input);
  if (u.scheme != 'https' ||
      u.host != 'github.com' ||
      u.userInfo.isNotEmpty ||
      !u.path.startsWith('/$releaseRepository/releases/')) {
    throw const FormatException('Недоверенный адрес обновления');
  }
  return u;
}

class AppRelease {
  AppRelease(this.version, this.page, this.assets);
  final String version;
  final Uri page;
  final Map<String, Uri> assets;
  factory AppRelease.fromJson(Map<String, dynamic> j) {
    final version = j['tag_name'] as String;
    if (!RegExp(r'^v\d+\.\d+\.\d+(?:-[A-Za-z0-9.]+)?$').hasMatch(version)) {
      throw const FormatException('Invalid release');
    }
    final assets = <String, Uri>{};
    for (final raw in j['assets'] as List) {
      final a = raw as Map;
      final name = a['name'] as String;
      if (name.contains('/') ||
          name.contains('\\') ||
          name == '.' ||
          name == '..') {
        throw const FormatException('Invalid asset');
      }
      final u = trustedReleaseUrl(a['browser_download_url'] as String);
      if (!u.path.startsWith(
        '/$releaseRepository/releases/download/$version/',
      )) {
        throw const FormatException('Wrong release');
      }
      assets[name] = u;
    }
    return AppRelease(
      version,
      trustedReleaseUrl(j['html_url'] as String),
      assets,
    );
  }
  String? assetFor(String platform, String arch) {
    if (platform == 'android') {
      return switch (arch) {
        'arm64' => 'app-arm64-v8a-release.apk',
        'arm' => 'app-armeabi-v7a-release.apk',
        'x64' => 'app-x86_64-release.apk',
        _ => 'app-release.apk',
      };
    }
    final prefix = 'FoxWay-$platform-';
    final candidates = assets.keys
        .where((n) => n.startsWith(prefix) && n.endsWith('.zip'))
        .toList();
    return candidates.length == 1 ? candidates.single : null;
  }
}

class UpdateService extends ChangeNotifier {
  AppRelease? available;
  String? error, downloadedPath, downloadedDigest;
  bool checking = false, downloading = false;
  bool previewChannel =
      const String.fromEnvironment('UPDATE_CHANNEL', defaultValue: 'preview') ==
      'preview';
  double? progress;
  DateTime? checkedAt;
  Timer? _timer;
  void start() {
    unawaited(check());
    _timer = Timer.periodic(const Duration(hours: 6), (_) => check());
  }

  Future<List<int>> _get(
    Uri url, {
    required int limit,
    bool redirects = false,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      var current = url;
      for (var hop = 0; hop < 5; hop++) {
        final req = await client
            .getUrl(current)
            .timeout(const Duration(seconds: 20));
        req.followRedirects = false;
        req.headers.set('User-Agent', 'FoxWay/$appVersion');
        final res = await req.close().timeout(const Duration(seconds: 30));
        if (redirects && [301, 302, 303, 307, 308].contains(res.statusCode)) {
          final next = current.resolve(res.headers.value('location') ?? '');
          if (next.scheme != 'https' ||
              next.userInfo.isNotEmpty ||
              ![
                'github.com',
                'release-assets.githubusercontent.com',
                'objects.githubusercontent.com',
              ].contains(next.host)) {
            throw const FormatException('Недоверенное перенаправление');
          }
          current = next;
          continue;
        }
        if (res.statusCode != 200) {
          throw HttpException('Обновления: HTTP ${res.statusCode}');
        }
        final data = <int>[];
        await for (final chunk in res.timeout(const Duration(seconds: 30))) {
          if (data.length + chunk.length > limit) {
            throw const FormatException('Ответ слишком большой');
          }
          data.addAll(chunk);
        }
        return data;
      }
      throw const FormatException('Слишком много перенаправлений');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> check() async {
    if (checking) return;
    checking = true;
    error = null;
    notifyListeners();
    try {
      final data =
          jsonDecode(
                utf8.decode(
                  await _get(
                    Uri.parse(
                      'https://api.github.com/repos/$releaseRepository/releases?per_page=20',
                    ),
                    limit: 1024 * 1024,
                  ),
                ),
              )
              as List;
      final releases =
          data
              .cast<Map<String, dynamic>>()
              .where(
                (j) =>
                    j['draft'] == false &&
                    (previewChannel || j['prerelease'] == false),
              )
              .map(AppRelease.fromJson)
              .where((r) => compareVersions(r.version, appVersion) > 0)
              .toList()
            ..sort((a, b) => compareVersions(b.version, a.version));
      available = releases.isEmpty ? null : releases.first;
      checkedAt = DateTime.now();
    } catch (_) {
      error =
          'Не удалось проверить обновления. Установленная версия продолжает работать.';
    } finally {
      checking = false;
      notifyListeners();
    }
  }

  /// Streams into an exclusive temp directory; exposes a file only after SHA-256 verification.
  Future<File> download(String asset) async {
    if (downloading) throw StateError('Загрузка уже выполняется');
    final release = available;
    if (release == null ||
        !release.assets.containsKey(asset) ||
        !release.assets.containsKey('SHA256SUMS.txt')) {
      throw StateError('Нет проверяемого обновления');
    }
    downloading = true;
    progress = null;
    error = null;
    notifyListeners();
    Directory? folder;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final sums = utf8.decode(
        await _get(
          release.assets['SHA256SUMS.txt']!,
          limit: 65536,
          redirects: true,
        ),
      );
      final matches = const LineSplitter()
          .convert(sums)
          .map((s) => RegExp(r'^([0-9a-f]{64})  (.+)$').firstMatch(s))
          .whereType<RegExpMatch>()
          .where((m) => m[2] == asset)
          .toList();
      if (matches.length != 1) {
        throw const FormatException('Нет однозначной контрольной суммы');
      }
      folder = await Directory.systemTemp.createTemp('foxway-update-');
      final file = File('${folder.path}/$asset.part');
      var url = release.assets[asset]!;
      HttpClientResponse? response;
      for (var hop = 0; hop < 5; hop++) {
        final req = await client
            .getUrl(url)
            .timeout(const Duration(seconds: 20));
        req.followRedirects = false;
        final res = await req.close().timeout(const Duration(seconds: 30));
        if ([301, 302, 303, 307, 308].contains(res.statusCode)) {
          final next = url.resolve(res.headers.value('location') ?? '');
          if (next.scheme != 'https' ||
              next.userInfo.isNotEmpty ||
              ![
                'github.com',
                'release-assets.githubusercontent.com',
                'objects.githubusercontent.com',
              ].contains(next.host)) {
            throw const FormatException('Неверный адрес файла');
          }
          url = next;
          continue;
        }
        if (res.statusCode != 200) {
          throw const HttpException('Загрузка не удалась');
        }
        response = res;
        break;
      }
      if (response == null || response.contentLength > 512 * 1024 * 1024) {
        throw const FormatException('Неверный размер файла');
      }
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final bytes in response.timeout(
          const Duration(seconds: 30),
        )) {
          received += bytes.length;
          if (received > 512 * 1024 * 1024) {
            throw const FormatException('Файл слишком большой');
          }
          sink.add(bytes);
          progress = response.contentLength > 0
              ? received / response.contentLength
              : null;
          notifyListeners();
        }
      } finally {
        await sink.close();
      }
      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString() != matches.single[1]) {
        throw const FormatException('Контрольная сумма не совпала');
      }
      final verified = await file.rename('${folder.path}/$asset');
      downloadedPath = verified.path;
      downloadedDigest = digest.toString();
      return verified;
    } catch (_) {
      if (folder != null) await folder.delete(recursive: true);
      error = 'Обновление не проверено и не будет установлено';
      rethrow;
    } finally {
      client.close(force: true);
      downloading = false;
      notifyListeners();
    }
  }

  bool _disposed = false;
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
