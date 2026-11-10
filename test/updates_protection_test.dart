import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxway/core/updates.dart';
import 'package:foxway/core/protection.dart';
import 'package:foxway/core/profile.dart';
import 'package:foxway/core/routing.dart';
import 'package:foxway/core/api.dart';
import 'package:foxway/core/controller.dart';
import 'package:foxway/core/storage.dart';
import 'core_test.dart' show link, awg, FakeEngine, FakeProbe, MemoryVault;

class FakeGuard extends NativeGuard {
  final events = <String>[];
  bool failBind = false;
  @override
  Future<void> arm(Profile p) async {
    events.add('arm');
  }

  @override
  Future<void> bind(Profile p) async {
    events.add('bind');
    if (failBind) throw StateError('guard bind failure');
  }

  @override
  Future<void> off() async {
    events.add('off');
  }
}

void main() {
  test(
    'Semver handles preview, stable, numeric components and build metadata',
    () {
      expect(compareVersions('v1.10.0', '1.9.9'), greaterThan(0));
      expect(
        compareVersions('v1.0.0-preview.10', '1.0.0-preview.2'),
        greaterThan(0),
      );
      expect(compareVersions('1.0.0', '1.0.0-rc.99'), greaterThan(0));
      expect(compareVersions('1.0.0+42', '1.0.0+1'), 0);
    },
  );
  test('Updater refuses foreign repositories, HTTP and malicious filenames', () {
    expect(
      () => trustedReleaseUrl('https://github.com/evil/vpn/releases/latest'),
      throwsFormatException,
    );
    expect(
      () => trustedReleaseUrl(
        'http://github.com/starscream001/vpn_app/releases/latest',
      ),
      throwsFormatException,
    );
    expect(
      () => AppRelease.fromJson({
        'tag_name': 'v1.0.0',
        'html_url':
            'https://github.com/starscream001/vpn_app/releases/tag/v1.0.0',
        'assets': [
          {
            'name': '../bad.exe',
            'browser_download_url':
                'https://github.com/starscream001/vpn_app/releases/download/v1.0.0/bad.exe',
          },
        ],
      }),
      throwsFormatException,
    );
  });
  test(
    'Platform update asset selection never chooses sources or unsigned iOS installer',
    () {
      final r = AppRelease(
        'v1.0.0',
        Uri.parse(
          'https://github.com/starscream001/vpn_app/releases/tag/v1.0.0',
        ),
        {
          'FoxWay-corresponding-source.tar.gz': Uri(),
          'FoxWay-linux-native.zip': Uri(),
          'FoxWay-iOS-unsigned-native.zip': Uri(),
        },
      );
      expect(r.assetFor('linux', 'x64'), 'FoxWay-linux-native.zip');
      expect(r.assetFor('android', 'arm64'), 'app-arm64-v8a-release.apk');
    },
  );
  test(
    'Existing bot mixed subscription imports only supported profiles and preserves expiry',
    () {
      final expiry = DateTime.utc(2030);
      final result = decodeSubscription(
        base64.encode(
          utf8.encode('$link\nhysteria2://secret@host:443\nvless://invalid'),
        ),
        'fixture',
        expiresAt: expiry,
      );
      expect(result.profiles.length, 1);
      expect(result.skipped, 2);
      expect(result.profiles.single.expiresAt, expiry);
      expect(
        () => decodeSubscription('trojan://unsupported', 'fixture'),
        throwsFormatException,
      );
    },
  );
  test('Strict mode keeps preferences but enforces no site/app bypass', () {
    const saved = RoutingPolicy(
      killSwitch: true,
      domains: ['example.com'],
      excludedApps: ['org.example.app'],
    );
    expect(saved.enforced.directDomains, isEmpty);
    expect(saved.enforced.excludedApps, isEmpty);
    expect(saved.domains, ['example.com']);
    expect(RoutingPolicy.fromJson(saved.toJson()).killSwitch, true);
  });
  test(
    'Failed native bind and automatic stops never release the persistent firewall',
    () async {
      final guard = FakeGuard()..failBind = true;
      final engine = ProtectedEngine(FakeEngine(), guard: guard);
      final p = parseProfiles(
        link.replaceFirst('example.com', '127.0.0.1'),
      ).single;
      await expectLater(
        engine.start(p, const RoutingPolicy(killSwitch: true).enforced),
        throwsStateError,
      );
      await engine.stop();
      expect(guard.events, ['arm', 'bind']);
      await engine.releaseProtection();
      expect(guard.events.last, 'off');
    },
  );
  test(
    'Controller failed checks retain protection until an explicit disconnect',
    () async {
      final guard = FakeGuard();
      final engine = ProtectedEngine(FakeEngine(), guard: guard);
      final c = FoxController(
        store: StateStore(MemoryVault()),
        engine: engine,
        probe: FakeProbe([false]),
      );
      await c.init();
      await c.importText(link.replaceFirst('example.com', '127.0.0.1'));
      await c.updateRouting(const RoutingPolicy(killSwitch: true));
      await c.connect();
      expect(c.state, ConnectionState.error);
      expect(guard.events, isNot(contains('off')));
      await c.disconnect();
      expect(guard.events.last, 'off');
      c.dispose();
    },
  );
  test(
    'Managed subscription URLs survive protected state round trip without entering reports',
    () async {
      final vault = MemoryVault();
      final c = FoxController(
        store: StateStore(vault),
        engine: FakeEngine(),
        probe: FakeProbe([]),
      );
      await c.init();
      c.subscriptions = [
        SubscriptionSource('https://sub.ilyamanik.ru/s/fixture'),
      ];
      await c.save();
      c.dispose();
      final restored = FoxController(
        store: StateStore(vault),
        engine: FakeEngine(),
        probe: FakeProbe([]),
      );
      await restored.init();
      expect(
        restored.subscriptions.single.url,
        'https://sub.ilyamanik.ru/s/fixture',
      );
      expect(restored.reports.pending, isEmpty);
      restored.dispose();
    },
  );
  test(
    'Update shutdown saves profiles and stops without disarming protection',
    () async {
      final guard = FakeGuard();
      final vault = MemoryVault();
      final c = FoxController(
        store: StateStore(vault),
        engine: ProtectedEngine(FakeEngine(), guard: guard),
        probe: FakeProbe([true]),
      );
      await c.init();
      await c.importText(link.replaceFirst('example.com', '127.0.0.1'));
      await c.updateRouting(const RoutingPolicy(killSwitch: true));
      await c.connect();
      expect(c.active, isNotNull);
      await c.stopForUpdate();
      expect(c.active, isNull);
      expect(guard.events, isNot(contains('off')));
      expect((await StateStore(vault).load())['profiles'], hasLength(1));
      c.dispose();
    },
  );
  test('AWG subscription expiry applies to raw configuration too', () {
    final expiry = DateTime.utc(2030);
    expect(
      decodeSubscription(
        awg,
        'fixture',
        expiresAt: expiry,
      ).profiles.single.expiresAt,
      expiry,
    );
  });
}
