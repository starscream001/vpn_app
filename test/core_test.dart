import 'dart:convert';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxway/core/api.dart';
import 'package:foxway/core/controller.dart';
import 'package:foxway/core/engine.dart';
import 'package:foxway/core/profile.dart';
import 'package:foxway/core/routing.dart';
import 'package:foxway/core/storage.dart';

const link =
    'vless://12345678-1234-1234-1234-123456789abc@example.com:443?security=reality&type=tcp&pbk=TEST_PUBLIC_KEY&sni=example.org&sid=abcd&fp=chrome#Test';
const awg = '''[Interface]
PrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
Address = 10.0.0.2/32
DNS = 1.1.1.1
Jc = 4
Jmin = 40
Jmax = 70
S1 = 10
S2 = 20
S3 = 0
S4 = 0
H1 = 1-100
H2 = 101-200
H3 = 201-300
H4 = 301-400
I1 = <b 0x01020304>
[Peer]
PublicKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
Endpoint = 192.0.2.1:51820
AllowedIPs = 0.0.0.0/0, ::/0
''';

class MemoryVault implements Vault {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class FakeEngine implements TunnelEngine {
  int starts = 0, stops = 0;
  bool up = false;
  @override
  Future<void> start(Profile p, RoutingPolicy policy) async {
    starts++;
    up = true;
  }

  @override
  Future<void> stop() async {
    stops++;
    up = false;
  }

  @override
  Future<Traffic> traffic() async => Traffic(1000, 100, up);
}

class FakeProbe implements QualityProbe {
  FakeProbe(this.results);
  final List<bool> results;
  @override
  Future<ProbeResult> check(TunnelEngine e) async {
    final ok = results.removeAt(0);
    return ProbeResult(
      ok,
      50,
      ok ? 100 : 0,
      ok ? 10 : 0,
      ok ? 'https_204' : 'https_failed',
    );
  }
}

class DelayedProbe implements QualityProbe {
  final result = Completer<ProbeResult>();
  @override
  Future<ProbeResult> check(TunnelEngine engine) => result.future;
}

void main() {
  test('VLESS Reality parses name and stable identity', () {
    final p = parseProfiles(link).single;
    expect(p.name, 'Test');
    expect(p.protocol, Protocol.vless);
    expect(p.id, parseProfiles(link).single.id);
  });
  test('base64 subscriptions deduplicate entries', () {
    expect(parseProfiles(base64.encode(utf8.encode('$link\n$link'))).length, 1);
  });
  test('AWG 2 fields and raw config survive without downconversion', () {
    final p = parseProfiles(awg).single;
    expect(p.config, awg.trim());
    expect(p.config, contains('I1 = <b'));
    expect(p.config, contains('H1 = 1-100'));
    expect(p.protocol, Protocol.amnezia);
  });
  test('reject executable hooks even when mixed case', () {
    expect(
      () =>
          parseProfiles(awg.replaceFirst('DNS =', 'postUP = rm -rf /\nDNS =')),
      throwsFormatException,
    );
  });
  test('reject empty partial and unsupported imports', () {
    for (final s in [
      '',
      '[Interface]\nAddress=10.0.0.1',
      link.replaceFirst('reality', 'none'),
      link.replaceFirst('tcp', 'xhttp'),
      link.replaceFirst('vless:', 'http:'),
    ]) {
      expect(() => parseProfiles(s), throwsFormatException);
    }
  });
  test('reject insecure TLS and missing reality parameters', () {
    expect(
      () => parseProfiles(link.replaceFirst('&sid=', '&allowInsecure=1&sid=')),
      throwsFormatException,
    );
    expect(
      () => parseProfiles(link.replaceFirst('pbk=TEST_PUBLIC_KEY', 'pbk=')),
      throwsFormatException,
    );
  });
  test('partial update retains missing working configurations', () {
    final p = parseProfiles(link).single.success(42);
    expect(
      mergeCatalog([p], [], now: DateTime.now()).single.lastSuccess,
      isNotNull,
    );
  });
  test('explicit revocation wins over a working cached profile', () {
    final p = parseProfiles(link).single.success(42);
    expect(
      mergeCatalog([p], [], revokedIds: {p.id}, now: DateTime.now()),
      isEmpty,
    );
  });
  test('older revision cannot overwrite a newer key', () {
    final old = Profile(
      id: 'id',
      name: 'new',
      protocol: Protocol.amnezia,
      config: awg,
      revision: 3,
    );
    final stale = Profile(
      id: 'id',
      name: 'old',
      protocol: Protocol.amnezia,
      config: awg,
      revision: 2,
    );
    expect(
      mergeCatalog([old], [stale], now: DateTime.now()).single.name,
      'new',
    );
  });
  test('expired subscription never ranks as a candidate', () {
    final p = Profile(
      id: 'x',
      name: 'x',
      protocol: Protocol.amnezia,
      config: awg,
      expiresAt: DateTime.utc(2020),
    );
    expect(rankProfiles([p], Protocol.auto, DateTime.now()), isEmpty);
  });
  test('manual mode never selects another protocol', () {
    expect(
      rankProfiles(
        [...parseProfiles(link), ...parseProfiles(awg)],
        Protocol.vless,
        DateTime.now(),
      ).single.protocol,
      Protocol.vless,
    );
  });
  test('Russian direct rules are scoped and quality always uses VPN', () {
    final j =
        jsonDecode(
              xrayConfig(link, const RoutingPolicy(domains: ['example.com'])),
            )
            as Map;
    final rules = j['routing']['rules'] as List;
    expect(rules.first['inboundTag'], ['foxway-quality']);
    expect(rules.first['outboundTag'], 'foxway-proxy');
    expect(
      rules[1]['domain'],
      containsAll([
        'domain:ru',
        'domain:xn--p1ai',
        'domain:su',
        'domain:example.com',
      ]),
    );
    expect(rules.last['outboundTag'], 'foxway-proxy');
    expect(
      (j['inbounds'] as List).any(
        (i) => i['tag'] == 'foxway-quality' && i['listen'] == '127.0.0.1',
      ),
      true,
    );
  });
  test('disabling direct mode removes Russian domain bypass', () {
    final j =
        jsonDecode(
              xrayConfig(link, const RoutingPolicy(russianSitesDirect: false)),
            )
            as Map;
    expect(
      (j['routing']['rules'] as List).any((r) => r['domain'] != null),
      false,
    );
  });
  test('domain editor rejects URL and route injection', () {
    expect(validateDomains('example.com example.com\nexample.ru'), [
      'example.com',
      'example.ru',
    ]);
    for (final bad in [
      'https://example.com',
      'domain:ru',
      'example.com/path',
      '*.com',
    ]) {
      expect(() => validateDomains(bad), throwsFormatException);
    }
  });
  test('API rejects plaintext and credentials', () {
    expect(() => requireHttps('http://example.com'), throwsFormatException);
    expect(
      () => requireHttps('https://secret@example.com'),
      throwsFormatException,
    );
  });
  test('state persists across new controller/store instance', () async {
    final vault = MemoryVault();
    final store = StateStore(vault);
    await store.save({
      'profiles': parseProfiles(awg).map((p) => p.toJson()).toList(),
    });
    final saved = await StateStore(vault).load();
    expect(
      Profile.fromJson(
        Map<String, dynamic>.from((saved['profiles'] as List).single),
      ).config,
      awg.trim(),
    );
  });
  test('unknown storage schema fails closed', () async {
    final vault = MemoryVault();
    vault.values['foxway.state.v1'] = '{"schema":9}';
    await expectLater(StateStore(vault).load(), throwsFormatException);
  });
  test('quality report is an allowlist without secrets and addresses', () {
    final j = QualityReport(
      profileId: 'opaque-id',
      protocol: 'amnezia',
      ok: true,
      latencyMs: 10,
      rxDelta: 50,
      txDelta: 20,
      reason: 'https_204',
    ).toJson();
    expect(j.keys.toSet(), {
      'profile_id',
      'protocol',
      'ok',
      'latency_ms',
      'rx_delta',
      'tx_delta',
      'reason',
      'at',
    });
  });
  test('report failure retains event and retries successfully', () async {
    var attempts = 0, writes = 0;
    final queue = ReportQueue(
      persist: () async {
        writes++;
      },
      send: (batch) async {
        attempts++;
        if (attempts == 1) throw Exception('offline');
      },
    );
    await queue.add(
      QualityReport(
        profileId: 'x',
        protocol: 'vless',
        ok: true,
        latencyMs: 10,
        rxDelta: 10,
        txDelta: 10,
        reason: 'https_204',
      ),
    );
    await queue.flush();
    expect(queue.pending.length, 1);
    await queue.flush();
    expect(queue.pending, isEmpty);
    expect(writes, 2);
  });
  test(
    'auto switches sequentially only after traffic check succeeds',
    () async {
      final engine = FakeEngine();
      final c = FoxController(
        store: StateStore(MemoryVault()),
        engine: engine,
        probe: FakeProbe([false, true]),
      );
      await c.init();
      await c.importText(link);
      await c.importText(awg);
      await c.connect();
      expect(engine.starts, 2);
      expect(engine.stops, 1);
      expect(c.state, ConnectionState.connected);
      expect(c.active!.protocol, Protocol.vless);
      expect(c.profiles.where((p) => p.lastSuccess != null).length, 1);
      c.dispose();
    },
  );
  test(
    'a tunnel with no valid internet response never shows connected',
    () async {
      final c = FoxController(
        store: StateStore(MemoryVault()),
        engine: FakeEngine(),
        probe: FakeProbe([false]),
      );
      await c.init();
      await c.importText(link);
      await c.connect();
      expect(c.state, ConnectionState.error);
      expect(c.active, isNull);
      c.dispose();
    },
  );
  test(
    'telemetry off by default and third party profile not reported',
    () async {
      final c = FoxController(
        store: StateStore(MemoryVault()),
        engine: FakeEngine(),
        probe: FakeProbe([true]),
      );
      await c.init();
      expect(c.telemetry, false);
      await c.setTelemetry(true);
      await c.importText(link);
      await c.connect();
      expect(c.reports.pending, isEmpty);
      await c.setTelemetry(false);
      expect(c.reports.pending, isEmpty);
      c.dispose();
    },
  );
  test(
    'revocation survives restart and rejects stale catalog replay',
    () async {
      final vault = MemoryVault();
      final c = FoxController(
        store: StateStore(vault),
        engine: FakeEngine(),
        probe: FakeProbe([]),
      );
      await c.init();
      final paid = {
        ...parseProfiles(link).single.toJson(),
        'id': 'paid',
        'expiresAt': '2099-01-01T00:00:00Z',
      };
      await c.applyCatalog({
        'schema': 1,
        'profiles': [paid],
      });
      expect(c.profiles.length, 1);
      await c.applyCatalog({
        'schema': 1,
        'profiles': [],
        'revoked_ids': ['paid'],
      });
      expect(c.profiles, isEmpty);
      c.dispose();
      final restored = FoxController(
        store: StateStore(vault),
        engine: FakeEngine(),
        probe: FakeProbe([]),
      );
      await restored.init();
      await restored.applyCatalog({
        'schema': 1,
        'profiles': [paid],
      });
      expect(restored.profiles, isEmpty);
      restored.dispose();
    },
  );
  test('malformed catalog cannot partially replace working profiles', () async {
    final c = FoxController(
      store: StateStore(MemoryVault()),
      engine: FakeEngine(),
      probe: FakeProbe([]),
    );
    await c.init();
    await c.importText(link);
    final before = c.profiles.single.config;
    await expectLater(
      c.applyCatalog({
        'schema': 1,
        'profiles': [
          {'id': 'broken'},
        ],
      }),
      throwsA(anything),
    );
    expect(c.profiles.single.config, before);
    c.dispose();
  });
  test(
    'manual disconnect during quality check cannot trigger auto reconnect',
    () async {
      final probe = DelayedProbe(), engine = FakeEngine();
      final c = FoxController(
        store: StateStore(MemoryVault()),
        engine: engine,
        probe: probe,
      );
      await c.init();
      await c.importText(link);
      c.active = c.profiles.single;
      c.state = ConnectionState.connected;
      c.failures = 2;
      c.lastSwitch = DateTime.now().subtract(const Duration(minutes: 3));
      engine.up = true;
      final polling = c.poll();
      await Future<void>.delayed(Duration.zero);
      await c.disconnect();
      probe.result.complete(const ProbeResult(false, 0, 0, 0, 'https_failed'));
      await polling;
      expect(engine.starts, 0);
      expect(c.state, ConnectionState.disconnected);
      expect(c.active, isNull);
      c.dispose();
    },
  );
}
