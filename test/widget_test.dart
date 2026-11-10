import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foxway/main.dart';
import 'package:foxway/core/controller.dart';
import 'package:foxway/core/storage.dart';
import 'core_test.dart' show MemoryVault, FakeEngine, FakeProbe;

void main() {
  setUpAll(() async {
    final text = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/inter.ttf'));
    await text.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  for (final size in [
    const Size(390, 844),
    const Size(844, 390),
    const Size(1100, 800),
  ]) {
    testWidgets('responsive navigation $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = FoxController(
        store: StateStore(MemoryVault()),
        engine: FakeEngine(),
        probe: FakeProbe([]),
      );
      await c.init();
      await tester.pumpWidget(FoxWay(controller: c));
      await tester.pumpAndSettle();
      expect(find.text('Не подключено'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Серверы').last);
      await tester.pumpAndSettle();
      expect(find.text('Добавить профиль'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Ещё').last);
      await tester.pumpAndSettle();
      expect(find.text('Российские сайты напрямую'), findsOneWidget);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
      c.dispose();
    });
  }
  testWidgets('large accessibility text does not overflow', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = FoxController(
      store: StateStore(MemoryVault()),
      engine: FakeEngine(),
      probe: FakeProbe([]),
    );
    await c.init();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            textScaler: TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: FoxShell(c: c),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
    c.dispose();
  });
  testWidgets('Strict protection confirmation scrolls at 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = FoxController(
      store: StateStore(MemoryVault()),
      engine: FakeEngine(),
      probe: FakeProbe([]),
    );
    await c.init();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(375, 812),
            textScaler: TextScaler.linear(2),
          ),
          child: FoxShell(c: c),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ещё').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Килл-свитч'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(
      tester.element(find.text('Килл-свитч')),
      alignment: 0.2,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Килл-свитч'));
    await tester.pumpAndSettle();
    expect(find.text('Включить строгую защиту?'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(c.routing.killSwitch, false);
    debugDefaultTargetPlatformOverride = null;
    c.dispose();
  });
  testWidgets('capture home for visual review', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = FoxController(
      store: StateStore(MemoryVault()),
      engine: FakeEngine(),
      probe: FakeProbe([]),
    );
    await c.init();
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: FoxWay(controller: c),
      ),
    );
    await tester.pumpAndSettle();
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/review').create(recursive: true);
      await File(
        'build/review/home.png',
      ).writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
    for (final entry in {
      'Подписка': 'subscription',
      'Ещё': 'settings',
    }.entries) {
      await tester.tap(find.text(entry.key).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          'build/review/${entry.value}.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
    debugDefaultTargetPlatformOverride = null;
    c.dispose();
  });
}
