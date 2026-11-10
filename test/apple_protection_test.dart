import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sing_box/sing_box.dart';
import 'package:sing_box/sing_box_platform_interface.dart';
import 'package:foxway/core/native_engines.dart';
import 'package:foxway/core/profile.dart';
import 'package:foxway/core/routing.dart';
import 'core_test.dart' show link;

class AppleFixture extends SingBoxPlatform {
  SingBoxServiceOptions? options;
  String? config;
  @override
  Future<SingBoxRuntimeInfo> initialize(SingBoxOptions options) async =>
      const SingBoxRuntimeInfo(
        singBoxVersion: 'fixture',
        status: SingBoxConnectionStatus.connected,
      );
  @override
  Stream<SingBoxConnectionState> watchState() => const Stream.empty();
  @override
  Stream<SingBoxConnectionStats> watchStats() => const Stream.empty();
  @override
  Future<bool> requestVpnPermission() async => true;
  @override
  Future<void> setServiceOptions(SingBoxServiceOptions value) async {
    options = value;
  }

  @override
  Future<void> start(String config, {bool disableMemoryLimit = false}) async {
    this.config = config;
  }

  @override
  Future<void> stop() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Apple strict mode requests on-demand and includeAllNetworks without optional bypass',
    () async {
      final before = SingBoxPlatform.instance;
      final fixture = AppleFixture();
      SingBoxPlatform.instance = fixture;
      const channel = MethodChannel('app.foxway/apple-awg');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => null);
      final engine = AppleTunnelEngine();
      try {
        await engine.start(
          parseProfiles(link).single,
          const RoutingPolicy(killSwitch: true).enforced,
        );
        expect(fixture.options!.includeAllNetworks, true);
        expect(fixture.options!.onDemand, true);
        expect(fixture.options!.excludeLocalNetworks, false);
        expect(fixture.options!.excludeApns, false);
        final config = jsonDecode(fixture.config!) as Map;
        expect(
          (config['route']['rules'] as List).any(
            (r) => (r as Map).containsKey('domain_suffix'),
          ),
          false,
        );
        expect(engine.httpProxy, startsWith('PROXY 127.0.0.1:'));
      } finally {
        await engine.dispose();
        SingBoxPlatform.instance = before;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
    },
  );
}
