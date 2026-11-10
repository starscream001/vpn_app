import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxway/core/controller.dart';
import 'package:foxway/core/engine.dart';
import 'package:foxway/core/profile.dart';
import 'package:foxway/core/routing.dart';
import 'package:foxway/core/storage.dart';
import 'core_test.dart'
    show link, FakeEngine, FakeProbe, MemoryVault, DelayedProbe;

class PendingEngine extends FakeEngine {
  final started = Completer<void>();
  final finish = Completer<void>();
  @override
  Future<void> start(Profile p, RoutingPolicy policy) async {
    starts++;
    started.complete();
    await finish.future;
    up = true; // Native start may complete after an earlier stop request.
  }
}

void main() {
  test(
    'Stop during native startup cancels attempts and cleans up late tunnel',
    () async {
      final engine = PendingEngine();
      final c = FoxController(
        store: StateStore(MemoryVault()),
        engine: engine,
        probe: FakeProbe([]),
      );
      await c.init();
      await c.importText(
        '$link\n${link.replaceFirst('example.com', 'second.example')}',
      );
      final connecting = c.connect();
      await engine.started.future;
      final stopping = c.disconnect();
      expect(c.state, ConnectionState.stopping);
      await c.connect(); // A second start cannot run while stopping.
      expect(engine.starts, 1);
      engine.finish.complete();
      await Future.wait([connecting, stopping]);
      expect(engine.up, false);
      expect(c.active, isNull);
      expect(c.state, ConnectionState.disconnected);
      expect(c.error, isNull);
      expect(engine.starts, 1);
      c.dispose();
    },
  );
  test(
    'Stop interrupts a pending quality check without waiting for its result',
    () async {
      final engine = FakeEngine(), probe = DelayedProbe();
      final c = FoxController(
        store: StateStore(MemoryVault()),
        engine: engine,
        probe: probe,
      );
      await c.init();
      await c.importText(link);
      final connecting = c.connect();
      await Future<void>.delayed(Duration.zero);
      expect(c.state, ConnectionState.checking);
      await c.disconnect();
      await connecting;
      expect(engine.up, false);
      expect(c.state, ConnectionState.disconnected);
      probe.result.complete(const ProbeResult(true, 1, 1, 1, 'https_204'));
      await Future<void>.delayed(Duration.zero);
      expect(c.active, isNull);
      expect(c.state, ConnectionState.disconnected);
      expect(engine.starts, 1);
      c.dispose();
    },
  );
}
