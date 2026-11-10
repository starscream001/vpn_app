import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sing_box/sing_box.dart';
import 'package:sing_box/sing_box_platform_interface.dart';
import 'package:foxway/core/native_engines.dart';
import 'package:foxway/core/profile.dart';
import 'package:foxway/core/routing.dart';
import 'core_test.dart' show awg;

class FakeAppleCore extends SingBoxPlatform {
  @override
  Future<SingBoxRuntimeInfo> initialize(SingBoxOptions options) async =>
      const SingBoxRuntimeInfo(singBoxVersion: 'fixture');
  @override
  Stream<SingBoxConnectionState> watchState() => const Stream.empty();
  @override
  Stream<SingBoxConnectionStats> watchStats() => const Stream.empty();
  @override
  Future<void> stop() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Apple AWG preserves obfuscation config and uses dedicated extension statistics',
    () async {
      final previous = SingBoxPlatform.instance;
      SingBoxPlatform.instance = FakeAppleCore();
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('app.foxway/apple-awg'),
            (call) async {
              calls.add(call.method);
              if (call.method == 'start') {
                expect((call.arguments as Map)['config'], awg.trim());
              }
              if (call.method == 'stats') {
                return {'up': true, 'rx': 4096, 'tx': 512};
              }
              return null;
            },
          );
      final engine = AppleTunnelEngine();
      try {
        await engine.start(parseProfiles(awg).single, const RoutingPolicy());
        final stats = await engine.traffic();
        expect(stats.up, true);
        expect(stats.rx, 4096);
        expect(stats.tx, 512);
        await engine.stop();
        expect(calls, ['start', 'stats', 'stats', 'stop']);
      } finally {
        await engine.dispose();
        SingBoxPlatform.instance = previous;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('app.foxway/apple-awg'),
              null,
            );
      }
    },
  );
  test('AWG does not silently discard domain exclusions', () async {
    final previous = SingBoxPlatform.instance;
    SingBoxPlatform.instance = FakeAppleCore();
    try {
      await expectLater(
        AppleTunnelEngine().start(
          parseProfiles(awg).single,
          const RoutingPolicy(domains: ['example.com']),
        ),
        throwsUnsupportedError,
      );
    } finally {
      SingBoxPlatform.instance = previous;
    }
  });
}
