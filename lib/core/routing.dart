import 'dart:convert';
import 'package:flutter_v2ray/flutter_v2ray.dart';

class RoutingPolicy {
  const RoutingPolicy({
    this.russianSitesDirect = true,
    this.killSwitch = false,
    this.domains = const [],
    this.excludedApps = const [],
  });
  final bool russianSitesDirect, killSwitch;
  RoutingPolicy get enforced => killSwitch
      ? const RoutingPolicy(russianSitesDirect: false, killSwitch: true)
      : this;
  final List<String> domains, excludedApps;
  Map<String, dynamic> toJson() => {
    'russianSitesDirect': russianSitesDirect,
    'killSwitch': killSwitch,
    'domains': domains,
    'excludedApps': excludedApps,
  };
  factory RoutingPolicy.fromJson(Map<String, dynamic> j) => RoutingPolicy(
    russianSitesDirect: j['russianSitesDirect'] != false,
    killSwitch: j['killSwitch'] == true,
    domains: List<String>.from(j['domains'] ?? []),
    excludedApps: List<String>.from(j['excludedApps'] ?? []),
  );
  List<String> get directDomains => [
    if (russianSitesDirect) ...['domain:ru', 'domain:xn--p1ai', 'domain:su'],
    ...domains.map((d) => 'domain:$d'),
  ];
}

List<String> validateDomains(String text) {
  final domains = text
      .split(RegExp(r'[\s,]+'))
      .where((s) => s.isNotEmpty)
      .toSet()
      .toList();
  if (domains.any(
    (d) => !RegExp(
      r'^(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z0-9-]{2,63}$',
    ).hasMatch(d),
  )) {
    throw const FormatException(
      'Введите домены без https:// и путей; для кириллицы используйте punycode',
    );
  }
  return domains;
}

String xrayConfig(String link, RoutingPolicy policy) {
  final config =
      jsonDecode(FlutterV2ray.parseFromURL(link).getFullConfiguration())
          as Map<String, dynamic>;
  final outbounds = (config['outbounds'] as List).cast<Map<String, dynamic>>();
  // Never assume parser-specific outbound tags.
  final proxy = outbounds.firstWhere((o) => o['protocol'] == 'vless');
  proxy['tag'] = 'foxway-proxy';
  outbounds.removeWhere((o) => o['tag'] == 'foxway-direct');
  outbounds.add({
    'tag': 'foxway-direct',
    'protocol': 'freedom',
    'settings': {},
  });
  config['routing'] = {
    'domainStrategy': 'AsIs',
    'rules': [
      {
        'type': 'field',
        'inboundTag': ['foxway-quality'],
        'outboundTag': 'foxway-proxy',
      },
      if (policy.directDomains.isNotEmpty)
        {
          'type': 'field',
          'domain': policy.directDomains,
          'outboundTag': 'foxway-direct',
        },
      {'type': 'field', 'network': 'tcp,udp', 'outboundTag': 'foxway-proxy'},
    ],
  };
  (config['inbounds'] as List).add({
    'tag': 'foxway-quality',
    'listen': '127.0.0.1',
    'port': 10809,
    'protocol': 'http',
    'settings': {},
  });
  config['log'] = {'loglevel': 'none'};
  // Domain sniffing is required for applications that connect to resolved IPs.
  for (final inbound in config['inbounds'] as List) {
    inbound['sniffing'] = {
      'enabled': true,
      'destOverride': ['http', 'tls', 'quic'],
      'routeOnly': true,
    };
  }
  return jsonEncode(config);
}
