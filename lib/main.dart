import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:ffi' show Abi;
import 'package:url_launcher/url_launcher.dart';
import 'core/updates.dart';
import 'core/protection.dart';
import 'dart:ui' show AppExitResponse;
import 'package:flutter/foundation.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'core/controller.dart';
import 'core/api.dart' show importErrorMessage;
import 'core/engine.dart';
import 'core/native_engines.dart';
import 'core/profile.dart';
import 'core/routing.dart';
import 'core/storage.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = FoxController(
    store: StateStore(SecureVault()),
    engine: ProtectedEngine(platformEngine()),
    probe: HttpsProbe(
      Uri.parse(
        const String.fromEnvironment(
          'QUALITY_URL',
          defaultValue: 'https://www.gstatic.com/generate_204',
        ),
      ),
    ),
  );
  runApp(FoxWay(controller: controller, updates: UpdateService()..start()));
  controller.init();
}

const bg = Color(0xff081117),
    surface = Color(0xff111c24),
    teal = Color(0xff00d1b2),
    ink = Color(0xffe6f7f5),
    muted = Color(0xffa6bac4);

class FoxWay extends StatelessWidget {
  const FoxWay({super.key, required this.controller, this.updates});
  final UpdateService? updates;
  final FoxController controller;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'FoxWay VPN',
    theme: ThemeData(
      fontFamily: "Inter",
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        primary: teal,
        onPrimary: bg,
        surface: surface,
        onSurface: ink,
        secondary: teal,
      ),
      textTheme: ThemeData.dark().textTheme.apply(
        fontFamily: "Inter",
        bodyColor: ink,
        displayColor: ink,
      ),
      cardTheme: const CardThemeData(
        color: surface,
        margin: EdgeInsets.symmetric(vertical: 6),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: Color(0xff16483f),
      ),
    ),
    home: FoxShell(c: controller, updates: updates),
  );
}

class FoxShell extends StatefulWidget {
  const FoxShell({super.key, required this.c, this.updates});
  final UpdateService? updates;
  final FoxController c;
  @override
  State<FoxShell> createState() => _FoxShellState();
}

class _FoxShellState extends State<FoxShell> {
  late final AppLifecycleListener _lifecycle;
  late final UpdateService updates = widget.updates ?? UpdateService();
  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await c.engine.stop();
        return AppExitResponse.exit;
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    updates.dispose();
    super.dispose();
  }

  int page = 0;
  FoxController get c => widget.c;
  final labels = ['Главная', 'Серверы', 'Подписка', 'Ещё'];
  final icons = [
    Icons.home_outlined,
    Icons.dns_outlined,
    Icons.workspace_premium_outlined,
    Icons.grid_view_outlined,
  ];
  Future<void> act(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e
                  .toString()
                  .replaceFirst('FormatException: ', '')
                  .replaceFirst('Bad state: ', ''),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([c, updates]),
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        backgroundColor: bg,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/fox-icon.png',
                width: 36,
                height: 36,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.shield_outlined, color: teal),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'FoxWay ',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(
                      text: 'VPN',
                      style: TextStyle(
                        color: teal,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'О приложении',
            icon: const Icon(Icons.info_outline),
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: 'FoxWay VPN',
              applicationVersion: appVersion,
              children: [
                const Text(
                  'Независимый VPN-клиент для пяти платформ. Native интеграции требуют проверки на устройствах.\n'
                  'AmneziaWG: Apache-2.0 / MIT. Xray: MPL-2.0. AndroidLibXrayLite: LGPL-3.0.\n'
                  'Исходники и условия: github.com/starscream001/vpn_app',
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: !c.ready
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(c.error ?? 'Открываем защищённое хранилище…'),
                ),
              )
            : LayoutBuilder(
                builder: (context, box) => Row(
                  children: [
                    if (box.maxWidth >= 760)
                      NavigationRail(
                        selectedIndex: page,
                        onDestinationSelected: (i) => setState(() => page = i),
                        labelType: NavigationRailLabelType.all,
                        destinations: List.generate(
                          4,
                          (i) => NavigationRailDestination(
                            icon: Icon(icons[i]),
                            label: Text(labels[i]),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 640),
                          child: ListView(
                            padding: const EdgeInsets.all(24),
                            children: [
                              if (defaultTargetPlatform !=
                                  TargetPlatform.android)
                                const Card(
                                  child: Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Text(
                                      'Экспериментальные native-туннели: iOS требует подписи расширений, desktop — прав на TUN. Поддержка протоколов зависит от платформы.',
                                    ),
                                  ),
                                ),
                              ...switch (page) {
                                0 => home(),
                                1 => servers(),
                                2 => subscription(),
                                _ => settings(),
                              },
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
      bottomNavigationBar: MediaQuery.sizeOf(context).width < 760
          ? NavigationBar(
              selectedIndex: page,
              onDestinationSelected: (i) => setState(() => page = i),
              destinations: List.generate(
                4,
                (i) => NavigationDestination(
                  icon: Icon(icons[i]),
                  label: labels[i],
                ),
              ),
            )
          : null,
    ),
  );
  List<Widget> home() {
    final connected = c.state == ConnectionState.connected;
    final busy =
        c.state == ConnectionState.connecting ||
        c.state == ConnectionState.checking;
    final status = switch (c.state) {
      ConnectionState.connected => 'Подключено',
      ConnectionState.connecting => 'Подключаем…',
      ConnectionState.checking => 'Проверяем интернет…',
      ConnectionState.stopping => 'Останавливаем…',
      ConnectionState.error => 'Не удалось подключиться',
      _ => 'Не подключено',
    };
    return [
      const SizedBox(height: 16),
      Center(
        child: Semantics(
          label: busy
              ? 'Отменить подключение'
              : connected
              ? 'Отключить VPN'
              : 'Подключить VPN',
          button: true,
          child: Container(
            width: 172,
            height: 172,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: connected ? const Color(0xff6dffa4) : teal,
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: teal.withValues(alpha: 0.12),
                  blurRadius: 36,
                  spreadRadius: 6,
                ),
              ],
            ),
            child: IconButton(
              tooltip: busy
                  ? 'Отменить подключение'
                  : connected
                  ? 'Отключить'
                  : 'Подключить',
              onPressed: c.state == ConnectionState.stopping
                  ? null
                  : () => act(connected || busy ? c.disconnect : c.connect),
              icon: busy
                  ? const SizedBox(
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(),
                    )
                  : Icon(
                      Icons.power_settings_new_rounded,
                      size: 68,
                      color: connected ? const Color(0xff6dffa4) : teal,
                    ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 24),
      Text(
        status,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
      ),
      if (busy)
        Center(
          child: TextButton.icon(
            onPressed: () => act(c.disconnect),
            icon: const Icon(Icons.close),
            label: const Text('Отменить подключение'),
          ),
        ),
      const SizedBox(height: 8),
      Text(
        c.active?.name ?? 'Одна кнопка. Надёжное соединение.',
        textAlign: TextAlign.center,
        style: const TextStyle(color: muted),
      ),
      if (c.error != null)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(
            c.error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xffffbd94)),
          ),
        ),
      const SizedBox(height: 24),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: Protocol.values
            .map(
              (p) => ChoiceChip(
                label: Text(switch (p) {
                  Protocol.auto => 'Авто',
                  Protocol.vless => 'VLESS',
                  Protocol.amnezia => 'Amnezia',
                }),
                selected: c.mode == p,
                onSelected: connected || busy
                    ? null
                    : (_) => act(() => c.select(p)),
              ),
            )
            .toList(),
      ),
      const SizedBox(height: 16),
      Card(
        child: ListTile(
          leading: const Icon(Icons.shield_outlined, color: teal),
          title: Text(
            c.active?.name ??
                (c.selectedId == null
                    ? 'Авто • рекомендуемый сервер'
                    : 'Выбранный сервер'),
          ),
          subtitle: Text(
            '${c.profiles.length} профилей • проверка HTTPS и трафика',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => setState(() => page = 1),
        ),
      ),
      if (connected)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Получено: ${bytes(c.traffic.rx)}     Отправлено: ${bytes(c.traffic.tx)}',
            ),
          ),
        ),
      if (c.routing.russianSitesDirect || c.routing.killSwitch)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            c.routing.killSwitch
                ? 'Строгая защита: все сайты и приложения через VPN'
                : c.active?.protocol == Protocol.amnezia
                ? 'Amnezia: российские сайты сейчас идут через VPN. Доменные исключения доступны в VLESS.'
                : 'VLESS: сайты .ru, .рф и .su — напрямую',
            style: const TextStyle(color: muted),
            textAlign: TextAlign.center,
          ),
        ),
      const SizedBox(height: 16),
      ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Image.asset(
          'assets/fox-mountains.jpg',
          height: 210,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox(height: 120),
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        'Ваш путь к свободной связи',
        textAlign: TextAlign.center,
        style: TextStyle(color: muted),
      ),
    ];
  }

  String bytes(int n) => n > 1024 * 1024
      ? '${(n / 1024 / 1024).toStringAsFixed(1)} МБ'
      : '${(n / 1024).toStringAsFixed(1)} КБ';
  List<Widget> servers() => [
    heading('Серверы'),
    const Text(
      'Рабочие конфигурации остаются на устройстве при обновлении приложения.',
      style: TextStyle(color: muted),
    ),
    const SizedBox(height: 16),
    FilledButton.icon(
      onPressed: importDialog,
      icon: const Icon(Icons.add),
      label: const Text('Добавить профиль'),
    ),
    Card(
      child: ListTile(
        leading: const Icon(Icons.auto_awesome_outlined, color: teal),
        title: const Text('Автоматически'),
        subtitle: const Text('Последний рабочий, затем резервные'),
        selected: c.selectedId == null,
        onTap: () => act(() => c.select(Protocol.auto)),
      ),
    ),
    if (c.profiles.isEmpty)
      const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Здесь появятся ваши серверы. Добавьте конфигурацию или привяжите подписку.',
        ),
      ),
    ...c.profiles.map(
      (p) => Card(
        child: ListTile(
          leading: Icon(
            p.protocol == Protocol.amnezia
                ? Icons.water_outlined
                : Icons.bolt_outlined,
            color: teal,
          ),
          title: Text(p.name),
          subtitle: Text(
            '${p.protocol == Protocol.amnezia ? 'AmneziaWG' : 'VLESS'} • ${p.latency == null ? 'ещё не проверен' : '${p.latency} мс'}',
          ),
          selected: c.selectedId == p.id,
          onTap: () => act(() => c.select(p.protocol, id: p.id)),
          trailing: IconButton(
            tooltip: 'Удалить профиль',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => act(() => c.remove(p.id)),
          ),
        ),
      ),
    ),
  ];
  List<Widget> subscription() => [
    heading('Подписка'),
    Card(
      child: ListTile(
        leading: const Icon(Icons.telegram),
        title: const Text('FoxWay в Telegram'),
        subtitle: const Text('@Ilyavpnadmin_bot • существующая подписка'),
        trailing: const Icon(Icons.open_in_new),
        onTap: () => act(() => openBot()),
      ),
    ),
    const SizedBox(height: 12),
    const Text(
      'Откройте бота → «Мои подписки» → скопируйте VPN-ссылку. Вернитесь в FoxWay и добавьте её. Токен бота приложению не нужен.',
      style: TextStyle(color: muted),
    ),
    const SizedBox(height: 16),
    FilledButton.icon(
      onPressed: importDialog,
      icon: const Icon(Icons.add_link),
      label: const Text('Добавить ссылку подписки'),
    ),
    const SizedBox(height: 12),
    OutlinedButton.icon(
      onPressed: c.subscriptions.isEmpty && c.token == null
          ? null
          : () => act(() async {
              await c.refreshSubscriptions();
              if (c.token != null) await c.refresh();
            }),
      icon: const Icon(Icons.refresh),
      label: const Text('Обновить серверы'),
    ),
    for (final source in c.subscriptions)
      Card(
        child: ListTile(
          leading: const Icon(Icons.sync),
          title: Text(Uri.parse(source.url).host),
          subtitle: Text(
            'Серверов: ${c.profiles.where((p) => p.source == source.id).length}'
            '${source.expiresAt == null ? '' : ' • до ${source.expiresAt!.toLocal().toString().split(' ').first}'}'
            '\nАвтообновление каждые 15 минут • несовместимых: ${source.skipped}',
          ),
        ),
      ),
    if (c.subscriptionNotice != null)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          c.subscriptionNotice!,
          style: const TextStyle(color: muted),
        ),
      ),
    const SizedBox(height: 20),
    const Text(
      'Сторонние профили',
      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
    ),
    const SizedBox(height: 8),
    const Text(
      'Можно добавить свой VLESS, HTTPS-подписку или AmneziaWG .conf. Доступные протоколы определяются профилем.',
      style: TextStyle(color: muted),
    ),
    const SizedBox(height: 12),
    OutlinedButton.icon(
      onPressed: importDialog,
      icon: const Icon(Icons.upload_file),
      label: const Text('Импортировать профиль'),
    ),
    const SizedBox(height: 20),
    if (c.apiUrl != null ||
        const String.fromEnvironment('FOXWAY_API_URL').isNotEmpty)
      TextButton(
        onPressed: linkDialog,
        child: const Text('Ввести код активации'),
      ),
  ];
  Future<void> openBot() async {
    if (!await launchUrl(
      Uri.parse('https://t.me/Ilyavpnadmin_bot'),
      mode: LaunchMode.externalApplication,
    )) {
      throw StateError('Не удалось открыть Telegram');
    }
  }

  List<Widget> settings() => [
    heading('Ещё'),
    Card(
      child: SwitchListTile(
        title: const Text('Российские сайты напрямую'),
        subtitle: const Text(
          'VLESS: .ru, .рф, .su. Для AmneziaWG пока недоступно. Другие домены можно добавить ниже.',
        ),
        value: c.routing.russianSitesDirect,
        onChanged: c.routing.killSwitch
            ? null
            : (v) => act(
                () => c.updateRouting(
                  RoutingPolicy(
                    russianSitesDirect: v,
                    killSwitch: c.routing.killSwitch,
                    domains: c.routing.domains,
                    excludedApps: c.routing.excludedApps,
                  ),
                ),
              ),
      ),
    ),
    Card(
      child: ListTile(
        leading: const Icon(Icons.language_outlined),
        title: const Text('Исключения сайтов'),
        subtitle: Text('${c.routing.domains.length} доменов • VLESS'),
        trailing: const Icon(Icons.chevron_right),
        onTap: c.routing.killSwitch ? null : domainDialog,
      ),
    ),
    Card(
      child: ListTile(
        leading: const Icon(Icons.apps_outlined),
        title: const Text('Исключения приложений'),
        subtitle: Text('${c.routing.excludedApps.length} приложений • Android'),
        trailing: const Icon(Icons.chevron_right),
        onTap:
            defaultTargetPlatform == TargetPlatform.android &&
                !c.routing.killSwitch
            ? appsDialog
            : null,
      ),
    ),
    Card(
      child: SwitchListTile(
        title: const Text('Килл-свитч'),
        subtitle: const Text(
          'Защита применяется при подключении: все сайты и приложения через VPN, исключения временно не действуют. При обрыве интернет остаётся заблокированным до явного отключения защиты.',
        ),
        value: c.routing.killSwitch,
        onChanged: (v) => act(() async {
          if (v && !await confirmProtection()) return;
          await c.updateRouting(
            RoutingPolicy(
              russianSitesDirect: c.routing.russianSitesDirect,
              domains: c.routing.domains,
              excludedApps: c.routing.excludedApps,
              killSwitch: v,
            ),
          );
        }),
      ),
    ),
    if (c.routing.killSwitch)
      OutlinedButton.icon(
        onPressed: () => act(
          defaultTargetPlatform == TargetPlatform.android
              ? () => AndroidEngine.channel.invokeMethod<void>('settings')
              : c.disconnect,
        ),
        icon: const Icon(Icons.lock_open),
        label: Text(
          defaultTargetPlatform == TargetPlatform.android
              ? 'Открыть системную блокировку Android'
              : 'Отключить VPN и разрешить интернет',
        ),
      ),
    if (defaultTargetPlatform == TargetPlatform.android)
      TextButton(
        onPressed: () =>
            act(() => AndroidEngine.channel.invokeMethod<void>('settings')),
        child: const Text('Системная блокировка Android'),
      ),
    updateCard(),
    Card(
      child: SwitchListTile(
        title: const Text('Отчёты о качестве'),
        subtitle: const Text(
          'В FoxWay: сервер, протокол, задержка и результат. Без ключей, сайтов и списка приложений. Требуется API.',
        ),
        value: c.telemetry,
        onChanged: (v) => act(() => c.setTelemetry(v)),
      ),
    ),
    const SizedBox(height: 12),
    Text(
      'Проверки каждые 30 секунд, пока приложение работает. В очереди отчётов: ${c.reports.pending.length}.',
      style: const TextStyle(color: muted),
    ),
  ];
  Future<bool> confirmProtection() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Включить строгую защиту?'),
          content: SingleChildScrollView(
            child: Text(
              defaultTargetPlatform == TargetPlatform.android
                  ? 'После включения откройте настройки Android и включите «Постоянная VPN» и «Блокировать без VPN». FoxWay проверит системный статус. Исключения приложений и сайтов временно отключатся.'
                  : 'При сбое или закрытии приложения интернет может остаться заблокированным. Для снятия защиты используйте «Отключить VPN и разрешить интернет». На desktop нужны административные права. На macOS будут закрыты существующие сетевые соединения для применения строгих правил. Исключения временно отключатся.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Включить'),
            ),
          ],
        ),
      ) ??
      false;

  Widget updateCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.system_update_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Обновления • $appVersion',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            updates.available == null
                ? (updates.checkedAt == null
                      ? 'Автоматическая проверка при запуске и каждые 6 часов'
                      : 'Новая версия пока не найдена')
                : 'Доступна ${updates.available!.version}',
          ),
          if (updates.error != null)
            Text(updates.error!, style: const TextStyle(color: muted)),
          if (updates.downloading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(value: updates.progress),
            ),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: updates.checking || updates.downloading
                    ? null
                    : () => act(updates.check),
                child: Text(
                  updates.checking ? 'Проверяем…' : 'Проверить сейчас',
                ),
              ),
              if (updates.available != null)
                FilledButton(
                  onPressed: updates.downloading
                      ? null
                      : () => act(installUpdate),
                  child: Text(
                    defaultTargetPlatform == TargetPlatform.iOS
                        ? 'Открыть канал установки'
                        : 'Скачать обновление',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            defaultTargetPlatform == TargetPlatform.iOS
                ? 'Обновление iPhone устанавливается через App Store/TestFlight. Канал появится после подписанного выпуска.'
                : 'Файл проверяется по SHA-256. Android откроет системный установщик; Windows/Linux предложат установку и перезапуск с откатом. На macOS пока открывается проверенный архив: автоматическая установка потребует подписанного канала.',
            style: const TextStyle(color: muted),
          ),
        ],
      ),
    ),
  );

  bool _installing = false;
  Future<void> installUpdate() async {
    if (_installing) return;
    setState(() => _installing = true);
    try {
      await _performInstallUpdate();
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  Future<void> _performInstallUpdate() async {
    final release = updates.available;
    if (release == null) return;
    if (Platform.isIOS) {
      const store = String.fromEnvironment('IOS_UPDATE_URL');
      if (store.isEmpty) {
        throw StateError(
          'Подписанный App Store/TestFlight выпуск ещё не настроен. Неподписанный .app не устанавливается как обновление.',
        );
      }
      final url = Uri.parse(store);
      if (url.scheme != 'https' ||
          !['apps.apple.com', 'testflight.apple.com'].contains(url.host)) {
        throw StateError('Неверный канал iOS');
      }
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw StateError('Не удалось открыть магазин');
      }
      return;
    }
    final arch = Abi.current() == Abi.androidArm64
        ? 'arm64'
        : Abi.current() == Abi.androidArm
        ? 'arm'
        : 'x64';
    final platform = Platform.isAndroid
        ? 'android'
        : Platform.isWindows
        ? 'windows'
        : Platform.isMacOS
        ? 'macos'
        : 'linux';
    final asset = release.assetFor(platform, arch);
    if (asset == null) throw StateError('Для этой платформы пока нет файла.');
    final file = await updates.download(asset);
    if (Platform.isAndroid) {
      await AndroidEngine.channel.invokeMethod<void>('installUpdate', {
        'path': file.path,
      });
    } else if (Platform.isMacOS) {
      await Process.run('/usr/bin/open', ['-R', file.path]);
    } else {
      if (!mounted) return;
      final approved =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Установить обновление?'),
              content: const Text(
                'FoxWay проверит и подготовит новый bundle, закроется и запустится снова. Настройки и подписки останутся в системном хранилище. Предыдущая версия сохранится рядом для отката. Если включён килл-свитч, блокировка сохранится до следующего подключения или явного снятия защиты.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Позже'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Установить и перезапустить'),
                ),
              ],
            ),
          ) ??
          false;
      if (!approved) return;
      final folder = File(Platform.resolvedExecutable).parent;
      final windows = Platform.isWindows;
      final helper = File(
        '${folder.path}/foxway-update.${windows ? 'ps1' : 'py'}',
      );
      final staged = await helper.copy(
        '${file.parent.path}/foxway-update.${windows ? 'ps1' : 'py'}',
      );
      final process = await Process.start(
        windows ? 'powershell.exe' : '/usr/bin/python3',
        [
          if (windows) ...['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File'],
          staged.path,
          if (windows) '-Archive',
          file.path,
          if (windows) '-Digest',
          updates.downloadedDigest!,
          if (windows) '-Target',
          folder.path,
          if (windows) '-AppPid',
          pid.toString(),
        ],
        mode: ProcessStartMode.detachedWithStdio,
        workingDirectory: file.parent.path,
      );
      unawaited(process.stderr.drain<void>());
      try {
        await process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .where((s) => s.trim() == 'READY')
            .first
            .timeout(const Duration(seconds: 60));
        final readyAt = DateTime.now();
        await c.stopForUpdate();
        if (DateTime.now().difference(readyAt) > const Duration(seconds: 100)) {
          throw StateError('Installer preparation timed out');
        }
      } catch (_) {
        process.kill();
        throw StateError(
          'Не удалось подготовить обновление. Приложение и данные не заменены.',
        );
      }
      exit(0);
    }
  }

  Widget heading(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text(
      t,
      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
    ),
  );
  Future<void> importDialog() async {
    final input = TextEditingController();
    String? error;
    var importing = false;
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => PopScope(
          canPop: !importing,
          child: AlertDialog(
            title: Text(
              importing ? 'Загружаем подписку…' : 'Добавить подключение',
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: input,
                      minLines: 3,
                      maxLines: 8,
                      decoration: InputDecoration(
                        labelText: 'VLESS, HTTPS-подписка или .conf',
                        errorMaxLines: 5,
                        errorText: error,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: () async {
                            final value = await Clipboard.getData(
                              Clipboard.kTextPlain,
                            );
                            input.text = value?.text ?? '';
                          },
                          icon: const Icon(Icons.content_paste),
                          label: const Text('Из буфера'),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final file = await openFile();
                            if (file != null) {
                              if (await file.length() > 1024 * 1024) {
                                set(() => error = 'Файл больше 1 МБ');
                                return;
                              }
                              input.text = await file.readAsString();
                            }
                          },
                          icon: const Icon(Icons.folder_open),
                          label: const Text('Из файла'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: importing ? null : () => Navigator.pop(context),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: importing
                    ? null
                    : () async {
                        set(() {
                          importing = true;
                          error = null;
                        });
                        try {
                          final messenger = ScaffoldMessenger.of(context);
                          await c.importText(input.text);
                          if (context.mounted) {
                            Navigator.pop(context);
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  c.subscriptionNotice ??
                                      'Подключение добавлено',
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            set(() {
                              importing = false;
                              error = importErrorMessage(e);
                            });
                          }
                        }
                      },
                child: Text(importing ? 'Загрузка…' : 'Добавить'),
              ),
            ],
          ),
        ),
      ),
    );
    await Navigator.of(context).push(route);
    await route.completed;
    input.dispose();
  }

  Future<void> domainDialog() async {
    final input = TextEditingController(text: c.routing.domains.join('\n'));
    String? error;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Сайты напрямую • VLESS'),
          content: SizedBox(
            width: 440,
            child: TextField(
              controller: input,
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(
                labelText: 'Домены, каждый с новой строки',
                hintText: 'example.com',
                errorText: error,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await c.updateRouting(
                    RoutingPolicy(
                      russianSitesDirect: c.routing.russianSitesDirect,
                      killSwitch: c.routing.killSwitch,
                      domains: validateDomains(input.text),
                      excludedApps: c.routing.excludedApps,
                    ),
                  );
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  set(() => error = e.toString());
                }
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    input.dispose();
  }

  Future<void> appsDialog() async {
    await act(() async {
      final apps =
          await AndroidEngine.channel.invokeListMethod<dynamic>('apps') ?? [];
      final selected = c.routing.excludedApps.toSet();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, set) => AlertDialog(
            title: const Text('Приложения без VPN'),
            content: SizedBox(
              width: 480,
              height: 400,
              child: ListView(
                children: apps.map((raw) {
                  final a = Map<String, dynamic>.from(raw as Map);
                  return CheckboxListTile(
                    title: Text(a['name'] as String),
                    value: selected.contains(a['id']),
                    onChanged: (v) => set(() {
                      v == true
                          ? selected.add(a['id'] as String)
                          : selected.remove(a['id']);
                    }),
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () async {
                  try {
                    await c.updateRouting(
                      RoutingPolicy(
                        russianSitesDirect: c.routing.russianSitesDirect,
                        killSwitch: c.routing.killSwitch,
                        domains: c.routing.domains,
                        excludedApps: selected.toList(),
                      ),
                    );
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(e.toString())));
                    }
                  }
                },
                child: const Text('Сохранить'),
              ),
            ],
          ),
        ),
      );
    });
  }

  Future<void> linkDialog() async {
    final endpoint = TextEditingController(
          text: c.apiUrl ?? const String.fromEnvironment('FOXWAY_API_URL'),
        ),
        code = TextEditingController();
    String? error;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Привязать FoxWay'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: endpoint,
                  decoration: const InputDecoration(
                    labelText: 'Адрес API (HTTPS)',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: code,
                  decoration: InputDecoration(
                    labelText: 'Одноразовый код из бота',
                    errorText: error,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await c.link(endpoint.text.trim(), code.text.trim());
                  if (context.mounted) Navigator.pop(context);
                } catch (_) {
                  set(
                    () => error =
                        'Не удалось привязать. Проверьте адрес API и код.',
                  );
                }
              },
              child: const Text('Привязать'),
            ),
          ],
        ),
      ),
    );
    endpoint.dispose();
    code.dispose();
  }
}
