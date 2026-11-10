import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxway/core/profile.dart';
import 'package:foxway/core/routing.dart';
import 'package:foxway/core/sing_config.dart';
import 'core_test.dart' show link, awg;

void main() {
  test('TUN captures both families; quality inbound cannot bypass VPN', () {
    final p = parseProfiles(link).single;
    final j =
        jsonDecode(
              singConfig(
                p,
                const RoutingPolicy(),
                desktop: true,
                probePort: 18081,
                apiPort: 18082,
                secret: 'fixture',
              ),
            )
            as Map;
    expect(j['inbounds'][0]['type'], 'tun');
    expect(j['inbounds'][0]['address'].length, 2);
    expect(j['route']['rules'][2]['inbound'], ['quality']);
    expect(j['route']['rules'][2]['outbound'], 'proxy');
    expect(
      j['experimental']['clash_api']['external_controller'],
      '127.0.0.1:18082',
    );
    expect(j['log']['disabled'], true);
  });
  test(
    'AWG is rejected without pretending plain WireGuard supports obfuscation',
    () {
      expect(
        () => singConfig(parseProfiles(awg).single, const RoutingPolicy()),
        throwsUnsupportedError,
      );
    },
  );
  test('native validation fixtures', () async {
    final key = base64Url
        .encode(List.generate(32, (i) => i + 1))
        .replaceAll('=', '');
    final p = parseProfiles(link.replaceFirst('TEST_PUBLIC_KEY', key)).single;
    await Directory('build/review').create(recursive: true);
    await File('build/review/sing-desktop.json').writeAsString(
      singConfig(
        p,
        const RoutingPolicy(),
        desktop: true,
        apiPort: 18082,
        probePort: 18081,
        secret: 'fixture',
      ),
    );
    await File(
      'build/review/sing-ios.json',
    ).writeAsString(singConfig(p, const RoutingPolicy()));
  });
}
