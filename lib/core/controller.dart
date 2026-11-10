import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api.dart';
import 'engine.dart';
import 'profile.dart';
import 'routing.dart';
import 'storage.dart';
import 'updates.dart' show appVersion;
import 'protection.dart';

enum ConnectionState { disconnected, connecting, connected, checking, error }

class FoxController extends ChangeNotifier {
  FoxController({
    required this.store,
    required this.engine,
    required this.probe,
  });
  final StateStore store;
  final TunnelEngine engine;
  final QualityProbe probe;
  List<Profile> profiles = [];
  List<SubscriptionSource> subscriptions = [];
  DateTime? _lastSubscriptionAttempt;
  String? subscriptionNotice;
  Set<String> revokedIds = {};
  DateTime? _lastRefresh;
  RoutingPolicy routing = const RoutingPolicy();
  Protocol mode = Protocol.auto;
  ConnectionState state = ConnectionState.disconnected;
  String? error, selectedId, apiUrl, token;
  Profile? active;
  bool ready = false, telemetry = false;
  int failures = 0;
  int _session = 0;
  Traffic traffic = const Traffic(0, 0, false);
  DateTime? lastSwitch;
  Timer? _timer;
  bool _busy = false, _polling = false;
  late ReportQueue reports;
  Future<void> _writes = Future.value();
  Future<void> init() async {
    try {
      final j = await store.load();
      profiles = (j['profiles'] as List? ?? [])
          .map((p) => Profile.fromJson(Map<String, dynamic>.from(p)))
          .toList();
      subscriptions = (j['subscriptions'] as List? ?? [])
          .map((s) => SubscriptionSource.fromJson(Map<String, dynamic>.from(s)))
          .toList();
      routing = RoutingPolicy.fromJson(
        Map<String, dynamic>.from(j['routing'] ?? {}),
      );
      mode = Protocol.values.byName(j['mode'] as String? ?? 'auto');
      revokedIds = Set<String>.from(j['revokedIds'] ?? []);
      selectedId = j['selectedId'] as String?;
      apiUrl = j['apiUrl'] as String?;
      token = j['token'] as String?;
      telemetry = j['telemetry'] == true;
      reports = ReportQueue(
        persist: save,
        send: (batch) async {
          if (!telemetry || apiUrl == null || token == null) {
            throw StateError('Reporting not configured');
          }
          await ApiClient(requireHttps(apiUrl!), token: token).request(
            '/v1/quality/reports',
            body: {'schema': 1, 'reports': batch},
          );
        },
        pending: (j['reports'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
      );
      // No automatic VPN start on launch; never alter a user's existing tunnel silently.
      ready = true;
      notifyListeners();
      _timer = Timer.periodic(const Duration(seconds: 30), (_) => poll());
    } catch (_) {
      error =
          'Не удалось открыть защищённое хранилище. Данные не перезаписаны.';
      notifyListeners();
    }
  }

  Future<void> save() {
    final snapshot = {
      'revokedIds': revokedIds.toList(),
      'profiles': profiles.map((p) => p.toJson()).toList(),
      'subscriptions': subscriptions.map((s) => s.toJson()).toList(),
      'routing': routing.toJson(),
      'mode': mode.name,
      'selectedId': selectedId,
      'apiUrl': apiUrl,
      'token': token,
      'telemetry': telemetry,
      'reports': reports.pending
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
    };
    _writes = _writes
        .catchError((Object _) {})
        .then((_) => store.save(snapshot));
    return _writes;
  }

  Future<void> importText(String text) async {
    if (text.trim().startsWith('https://')) {
      final source = SubscriptionSource(requireHttps(text.trim()).toString());
      await _refreshSource(source);
      subscriptions.removeWhere((s) => s.id == source.id);
      subscriptions.add(source);
    } else {
      profiles = mergeCatalog(
        profiles,
        parseProfiles(text),
        now: DateTime.now(),
      );
    }
    await save();
    notifyListeners();
  }

  Future<void> _refreshSource(SubscriptionSource source) async {
    final download = await fetchSubscription(source.url);
    // Expiry from the trusted subscription response updates even an unchanged URI.
    final ids = download.profiles.map((p) => p.id).toSet();
    final configs = download.profiles.map((p) => p.config).toSet();
    profiles = mergeCatalog(
      profiles
          .where(
            (p) =>
                !(p.source == source.id &&
                    (ids.contains(p.id) || configs.contains(p.config))),
          )
          .map(
            (p) => p.source == source.id && download.expiresAt != null
                ? Profile.fromJson({
                    ...p.toJson(),
                    'expiresAt': download.expiresAt!.toIso8601String(),
                  })
                : p,
          )
          .toList(),
      download.profiles.map((p) {
        final previous = profiles
            .where(
              (old) =>
                  old.id == p.id ||
                  (old.source == source.id && old.config == p.config),
            )
            .firstOrNull;
        return Profile.fromJson({
          ...p.toJson(),
          if (previous?.lastSuccess != null)
            'lastSuccess': previous!.lastSuccess!.toIso8601String(),
          if (previous?.latency != null) 'latency': previous!.latency,
        });
      }).toList(),
      now: DateTime.now(),
    );
    source.lastSuccess = DateTime.now();
    source.skipped = download.skipped;
    subscriptionNotice = download.skipped > 0
        ? 'Импортировано ${download.profiles.length}; несовместимых профилей: ${download.skipped}'
        : null;
  }

  Future<void> refreshSubscriptions() async {
    var failed = false;
    for (final source in subscriptions) {
      try {
        await _refreshSource(source);
      } catch (_) {
        failed = true;
      }
    }
    if (failed) {
      subscriptionNotice =
          'Подписка временно недоступна. Последние рабочие профили сохранены.';
    }
    await save();
    notifyListeners();
  }

  Future<void> updateRouting(RoutingPolicy policy) async {
    if (active != null || _busy) throw StateError('Сначала отключите VPN');
    if (routing.killSwitch &&
        !policy.killSwitch &&
        engine is ProtectionControl) {
      await (engine as ProtectionControl).releaseProtection();
    }
    routing = policy;
    await save();
    notifyListeners();
  }

  Future<void> select(Protocol value, {String? id}) async {
    if (active != null || _busy) throw StateError('Сначала отключите VPN');
    mode = value;
    selectedId = id;
    await save();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    if (active?.id == id || _busy) throw StateError('Сначала отключите VPN');
    profiles.removeWhere((p) => p.id == id);
    if (selectedId == id) selectedId = null;
    await save();
    notifyListeners();
  }

  Future<void> link(String endpoint, String code) async {
    final base = requireHttps(endpoint);
    final res = await ApiClient(base).request(
      '/v1/auth/exchange',
      body: {'code': code, 'client': 'foxway', 'version': appVersion},
    );
    final access = res['access_token'];
    if (access is! String || access.isEmpty) {
      throw const FormatException('API не вернул токен');
    }
    apiUrl = base.toString();
    token = access;
    await save();
    await refresh();
  }

  Future<void> refresh() async {
    if (apiUrl == null || token == null) {
      throw StateError('Сначала привяжите подписку');
    }
    final res = await ApiClient(
      requireHttps(apiUrl!),
      token: token,
    ).request('/v1/catalog');
    await applyCatalog(res);
    _lastRefresh = DateTime.now();
  }

  Future<void> applyCatalog(Map<String, dynamic> res) async {
    if (res['schema'] != 1 || res['profiles'] is! List) {
      throw const FormatException('Неверный каталог');
    }
    final incoming = (res['profiles'] as List).map((raw) {
      final p = Profile.fromJson({
        ...Map<String, dynamic>.from(raw),
        'source': 'foxway',
      });
      final parsed = parseProfiles(p.config);
      if (parsed.single.protocol != p.protocol ||
          p.protocol == Protocol.auto ||
          p.expiresAt == null) {
        throw const FormatException('Неверный профиль каталога');
      }
      return p;
    }).toList();
    revokedIds.addAll(Set<String>.from(res['revoked_ids'] ?? []));
    revokedIds.addAll(incoming.where((p) => p.revoked).map((p) => p.id));
    profiles = mergeCatalog(
      profiles,
      incoming,
      revokedIds: revokedIds,
      now: DateTime.now(),
    );
    if (active != null &&
        !profiles.any(
          (p) => p.id == active!.id && p.config == active!.config,
        )) {
      await disconnect(releaseProtection: false);
    }
    await save();
    notifyListeners();
  }

  Future<void> setTelemetry(bool value) async {
    telemetry = value;
    if (!value) reports.pending.clear();
    await save();
    notifyListeners();
  }

  Future<void> _record(Profile p, ProbeResult r) async {
    if (r.ok) {
      profiles = profiles
          .map((old) => old.id == p.id ? old.success(r.ms) : old)
          .toList();
    }
    if (telemetry && p.source == 'foxway') {
      await reports.add(
        QualityReport(
          profileId: p.id,
          protocol: p.protocol.name,
          ok: r.ok,
          latencyMs: r.ms,
          rxDelta: r.rx,
          txDelta: r.tx,
          reason: r.reason,
        ),
      );
    }
    await save();
  }

  Future<void> connect({String? skipId}) async {
    if (_busy || !ready) return;
    _busy = true;
    _session++;
    error = null;
    state = ConnectionState.connecting;
    notifyListeners();
    try {
      final candidates = rankProfiles(profiles, mode, DateTime.now())
          .where(
            (p) => p.id != skipId && (selectedId == null || p.id == selectedId),
          )
          .take(4)
          .toList();
      if (routing.killSwitch && engine is ProtectionControl) {
        await (engine as ProtectionControl).prepareProtection(candidates);
      }
      if (candidates.isEmpty) throw StateError('Добавьте профиль или подписку');
      for (final p in candidates) {
        try {
          await engine.start(p, routing.enforced);
          state = ConnectionState.checking;
          notifyListeners();
          final result = await probe.check(engine);
          await _record(p, result);
          if (result.ok) {
            error = null;
            active = p;
            failures = 0;
            lastSwitch = DateTime.now();
            state = ConnectionState.connected;
            return;
          }
        } catch (e) {
          error = e is UnsupportedError
              ? e.message.toString()
              : 'Подключение не удалось';
          await _record(p, const ProbeResult(false, 0, 0, 0, 'start_failed'));
        }
        await engine.stop();
        if (mode != Protocol.auto || selectedId != null) break;
      }
      throw StateError(
        error ?? 'Нет ответа через VPN. Проверьте профиль и сеть.',
      );
    } catch (e) {
      error = e.toString().replaceFirst('Bad state: ', '');
      state = ConnectionState.error;
      await engine.stop();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> disconnect({bool releaseProtection = true}) async {
    if (_busy) return;
    _session++;
    if (releaseProtection &&
        routing.killSwitch &&
        engine is ProtectionControl) {
      await (engine as ProtectionControl).releaseProtection();
    } else {
      await engine.stop();
    }
    active = null;
    traffic = const Traffic(0, 0, false);
    state = ConnectionState.disconnected;
    notifyListeners();
  }

  Future<void> poll() async {
    if (_busy || _polling || !ready) return;
    _polling = true;
    try {
      if (apiUrl != null &&
          token != null &&
          (_lastRefresh == null ||
              DateTime.now().difference(_lastRefresh!).inMinutes >= 15)) {
        // Failed refresh retains cached catalog and throttles the next retry.
        _lastRefresh = DateTime.now();
        try {
          await refresh();
        } catch (_) {}
      }
      if (subscriptions.isNotEmpty &&
          (_lastSubscriptionAttempt == null ||
              DateTime.now().difference(_lastSubscriptionAttempt!).inMinutes >=
                  15)) {
        _lastSubscriptionAttempt = DateTime.now();
        await refreshSubscriptions();
      }
      profiles.removeWhere((p) => !p.usable(DateTime.now()));
      if (active != null) {
        if (!profiles.any((p) => p.id == active!.id)) {
          await disconnect(releaseProtection: false);
          await save();
          return;
        }
        final p = active!;
        final session = _session;
        final r = await probe.check(engine);
        if (session != _session || active?.id != p.id) return;
        await _record(p, r);
        traffic = await engine.traffic();
        failures = r.ok ? 0 : failures + 1;
        if (failures >= 3) {
          error = 'Связь нестабильна';
          if (mode == Protocol.auto &&
              selectedId == null &&
              DateTime.now().difference(lastSwitch!).inMinutes >= 2) {
            // Demote failed candidate for this bounded reconnect attempt.

            await disconnect(releaseProtection: false);
            await connect(skipId: p.id);

            await save();
          }
        }
      }
      await reports.flush();
      notifyListeners();
    } catch (_) {
      error = 'Не удалось выполнить проверку соединения';
      notifyListeners();
    } finally {
      _polling = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
