import 'dart:convert';
import 'profile.dart';
import 'routing.dart';

String singConfig(
  Profile profile,
  RoutingPolicy policy, {
  bool desktop = false,
  bool proxyProbe = false,
  int probePort = 10809,
  int apiPort = 0,
  String secret = '',
}) {
  if (profile.protocol != Protocol.vless) {
    throw UnsupportedError(
      'На этой платформе пока доступен VLESS/Reality; AmneziaWG требует отдельного движка.',
    );
  }
  if (policy.excludedApps.isNotEmpty) {
    throw UnsupportedError('Исключения приложений доступны только на Android.');
  }
  final u = Uri.parse(profile.config),
      q = Uri.parse(profile.config).queryParameters;
  final tls = <String, dynamic>{
    'enabled': true,
    'server_name': q['sni'] ?? u.host,
    'utls': {'enabled': true, 'fingerprint': q['fp'] ?? 'chrome'},
  };
  if (q['security'] == 'reality') {
    tls['reality'] = {
      'enabled': true,
      'public_key': q['pbk'],
      'short_id': q['sid'] ?? '',
    };
  }
  final proxy = <String, dynamic>{
    'type': 'vless',
    'tag': 'proxy',
    'server': u.host,
    'server_port': u.port,
    'uuid': u.userInfo,
    'tls': tls,
    if ((q['flow'] ?? '').isNotEmpty) 'flow': q['flow'],
  };
  return jsonEncode({
    'log': {'disabled': true},
    'dns': {
      'servers': [
        {'type': 'udp', 'tag': 'bootstrap', 'server': '1.1.1.1'},
        {
          'type': 'https',
          'tag': 'secure-dns',
          'server': '1.1.1.1',
          'path': '/dns-query',
          'detour': 'proxy',
        },
      ],
      'final': 'secure-dns',
      'strategy': 'prefer_ipv4',
    },
    'inbounds': [
      {
        'type': 'tun',
        'tag': 'tun-in',
        'address': ['172.30.89.1/30', 'fd89:1234::1/126'],
        'mtu': 1400,
        'auto_route': true,
        'strict_route': true,
        'stack': 'system',
      },
      if (desktop || proxyProbe)
        {
          'type': 'http',
          'tag': 'quality',
          'listen': '127.0.0.1',
          'listen_port': probePort,
        },
    ],
    'outbounds': [
      proxy,
      {'type': 'direct', 'tag': 'direct'},
    ],
    'route': {
      'auto_detect_interface': desktop,
      'default_domain_resolver': 'bootstrap',
      'rules': [
        {'action': 'sniff'},
        {'protocol': 'dns', 'action': 'hijack-dns'},
        if (desktop || proxyProbe)
          {
            'inbound': ['quality'],
            'outbound': 'proxy',
          },
        if (policy.directDomains.isNotEmpty)
          {
            'domain_suffix': policy.directDomains
                .map((d) => d.substring(7))
                .toList(),
            'outbound': 'direct',
          },
      ],
      'final': 'proxy',
    },
    if (desktop)
      'experimental': {
        'clash_api': {
          'external_controller': '127.0.0.1:$apiPort',
          'secret': secret,
        },
      },
  });
}
