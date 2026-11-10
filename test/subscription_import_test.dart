import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxway/core/api.dart';
import 'package:foxway/core/controller.dart';
import 'package:foxway/core/storage.dart';
import 'package:foxway/core/profile.dart' show configId;
import 'core_test.dart' show link, FakeEngine, FakeProbe, MemoryVault;

class Headers extends Fake implements HttpHeaders {
  Headers([this.values = const {}]);
  final Map<String, String> values;
  @override
  String? value(String name) => values[name];
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class Response extends Stream<List<int>> implements HttpClientResponse {
  Response(this.statusCode, this.body, [Map<String, String> headers = const {}])
    : headers = Headers(headers);
  final String body;
  @override
  final int statusCode;
  @override
  final HttpHeaders headers;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(utf8.encode(body)).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Request extends Fake implements HttpClientRequest {
  Request(this.response);
  final Response response;
  @override
  final HttpHeaders headers = Headers();
  @override
  bool followRedirects = false;
  @override
  Future<HttpClientResponse> close() async => response;
}

class Client extends Fake implements HttpClient {
  Client(this.responses);
  final List<Response> responses;
  final urls = <Uri>[];
  bool closed = false;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    urls.add(url);
    return Request(responses.removeAt(0));
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }
}

void main() {
  const url = 'https://subscription.example/s/private-fixture-token';
  test(
    'HTTPS redirect imports base64 subscription and expiry under original source',
    () async {
      final client = Client([
        Response(302, '', {'location': '/download'}),
        Response(
          200,
          base64.encode(utf8.encode('$link\ntrojan://unsupported')),
          {'subscription-userinfo': 'upload=4; download=8; expire=1893456000'},
        ),
      ]);
      final result = await fetchSubscription(url, httpClient: client);
      expect(result.profiles, hasLength(1));
      expect(result.skipped, 1);
      expect(result.expiresAt, DateTime.utc(2030));
      expect(
        client.urls.last.toString(),
        'https://subscription.example/download',
      );
      expect(client.closed, true);
    },
  );
  test('Redirect to HTTP fails before sending a request', () async {
    final client = Client([
      Response(302, '', {'location': 'http://unsafe.example/'}),
    ]);
    await expectLater(
      fetchSubscription(url, httpClient: client),
      throwsA(isA<SubscriptionImportException>()),
    );
    expect(client.urls, hasLength(1));
    expect(client.closed, true);
  });
  test('Redirect loops are bounded', () async {
    final client = Client(
      List.generate(6, (_) => Response(302, '', {'location': '/again'})),
    );
    await expectLater(
      fetchSubscription(url, httpClient: client),
      throwsA(isA<SubscriptionImportException>()),
    );
    expect(client.urls, hasLength(6));
  });
  test(
    'HTTP, HTML, empty and oversized responses explain failures without credentials',
    () async {
      for (final response in [
        Response(403, 'private-body'),
        Response(404, ''),
        Response(429, ''),
        Response(503, ''),
        Response(200, '<html>private-body</html>'),
        Response(200, ''),
        Response(200, 'x' * (1024 * 1024 + 1)),
      ]) {
        try {
          await fetchSubscription(url, httpClient: Client([response]));
          fail('Import should fail');
        } on SubscriptionImportException catch (e) {
          expect(e.message, isNot(contains('private')));
          expect(e.message, isNot(contains('subscription.example')));
        }
      }
      expect(
        importErrorMessage(const SocketException(url)),
        isNot(contains(url)),
      );
      expect(importErrorMessage(TimeoutException(url)), isNot(contains(url)));
      expect(
        importErrorMessage(const FormatException(url)),
        isNot(contains(url)),
      );
    },
  );
  test(
    'Pasted subscription persists, repeated import deduplicates, failed refresh keeps servers',
    () async {
      final vault = MemoryVault();
      var failLoad = false;
      final c = FoxController(
        store: StateStore(vault),
        engine: FakeEngine(),
        probe: FakeProbe([]),
        subscriptionLoader: (url) async {
          if (failLoad) throw const SocketException('private-url');
          return decodeSubscription(
            link,
            configId(url),
            expiresAt: DateTime.utc(2030),
          );
        },
      );
      await c.init();
      await c.importText(url);
      await c.importText(url);
      expect(c.subscriptions, hasLength(1));
      expect(c.profiles, hasLength(1));
      expect(c.subscriptionNotice, contains('1'));
      failLoad = true;
      await c.refreshSubscriptions();
      expect(c.profiles, hasLength(1));
      c.dispose();
      final restored = FoxController(
        store: StateStore(vault),
        engine: FakeEngine(),
        probe: FakeProbe([]),
      );
      await restored.init();
      expect(restored.subscriptions.single.url, url);
      expect(restored.subscriptions.single.expiresAt, DateTime.utc(2030));
      expect(restored.profiles, hasLength(1));
      restored.dispose();
    },
  );
}
