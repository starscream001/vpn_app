import 'dart:ui' show AppExitResponse;
import 'package:flutter/foundation.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'core/controller.dart';
import 'core/engine.dart';
import 'core/native_engines.dart';
import 'core/profile.dart';
import 'core/routing.dart';
import 'core/storage.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = FoxController(
    store: StateStore(SecureVault()),
    engine: platformEngine(),
    probe: HttpsProbe(
      Uri.parse(
        const String.fromEnvironment(
          'QUALITY_URL',
          defaultValue: 'https://www.gstatic.com/generate_204',
        ),
      ),
    ),
  );
  runApp(FoxWay(controller: controller));
  controller.init();
}

const bg = Color(0xff081117),
    surface = Color(0xff111c24),
    teal = Color(0xff00d1b2),
    ink = Color(0xffe6f7f5),
    muted = Color(0xffa6bac4);

class FoxWay extends StatelessWidget {
  const FoxWay({super.key, required this.controller});
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
    home: FoxShell(c: controller),
  );
}

class FoxShell extends StatefulWidget {
  const FoxShell({super.key, required this.c});
  final FoxController c;
  @override
  State<FoxShell> createState() => _FoxShellState();
}

class _FoxShellState extends State<FoxShell> {
  late final AppLifecycleListener _lifecycle;
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
    listenable: c,
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
              applicationVersion: '0.1.0 • Android preview',
              children: [
                const Text(
                  'Независимый клиент. Системные туннели пока реализованы для Android.\n'
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
      ConnectionState.error => 'Не удалось подключиться',
      _ => 'Не подключено',
    };
    return [
      const SizedBox(height: 16),
      Center(
        child: Semantics(
          label: connected ? 'Отключить VPN' : 'Подключить VPN',
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
              tooltip: connected ? 'Отключить' : 'Подключить',
              onPressed: busy
                  ? null
                  : () => act(connected ? c.disconnect : c.connect),
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
      if (c.routing.russianSitesDirect)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            c.active?.protocol == Protocol.amnezia
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
        leading: const Icon(Icons.workspace_premium_outlined, color: teal),
        title: Text(c.token == null ? 'Привяжите FoxWay' : 'FoxWay привязан'),
        subtitle: const Text('Одноразовый код из Telegram-бота'),
      ),
    ),
    const SizedBox(height: 16),
    FilledButton.icon(
      onPressed: linkDialog,
      icon: const Icon(Icons.link),
      label: const Text('Ввести код из Telegram'),
    ),
    const SizedBox(height: 12),
    OutlinedButton.icon(
      onPressed: c.token == null ? null : () => act(c.refresh),
      icon: const Icon(Icons.refresh),
      label: const Text('Обновить серверы'),
    ),
    const SizedBox(height: 24),
    const Text(
      'Сторонние профили',
      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
    ),
    const SizedBox(height: 8),
    const Text(
      'Работают независимо от подписки FoxWay. Импортируйте VLESS-ссылку, HTTPS-подписку или файл AmneziaWG.',
      style: TextStyle(color: muted),
    ),
    const SizedBox(height: 12),
    OutlinedButton.icon(
      onPressed: importDialog,
      icon: const Icon(Icons.add),
      label: const Text('Добавить сторонний профиль'),
    ),
    const SizedBox(height: 24),
    const Text(
      'Интеграция с ботом требует адреса API FoxWay. Токен бота в приложение не передаётся.',
      style: TextStyle(color: muted),
    ),
  ];
  List<Widget> settings() => [
    heading('Ещё'),
    Card(
      child: SwitchListTile(
        title: const Text('Российские сайты напрямую'),
        subtitle: const Text(
          'VLESS: .ru, .рф, .su. Для AmneziaWG пока недоступно. Другие домены можно добавить ниже.',
        ),
        value: c.routing.russianSitesDirect,
        onChanged: (v) => act(
          () => c.updateRouting(
            RoutingPolicy(
              russianSitesDirect: v,
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
        onTap: domainDialog,
      ),
    ),
    Card(
      child: ListTile(
        leading: const Icon(Icons.apps_outlined),
        title: const Text('Исключения приложений'),
        subtitle: Text('${c.routing.excludedApps.length} приложений • Android'),
        trailing: const Icon(Icons.chevron_right),
        onTap: defaultTargetPlatform == TargetPlatform.android
            ? appsDialog
            : null,
      ),
    ),
    Card(
      child: ListTile(
        leading: const Icon(Icons.security_outlined),
        title: const Text('Защита при обрыве'),
        subtitle: const Text(
          'Откройте настройки Android: постоянная VPN и блокировка без VPN. Совместимость зависит от движка; требует проверки на устройстве.',
        ),
        onTap: defaultTargetPlatform == TargetPlatform.android
            ? () => act(
                () => AndroidEngine.channel.invokeMethod<void>('settings'),
              )
            : null,
      ),
    ),
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
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Добавить подключение'),
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
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await c.importText(input.text);
                  if (context.mounted) Navigator.pop(context);
                } catch (_) {
                  set(
                    () => error =
                        'Не удалось импортировать. Проверьте формат или HTTPS-адрес.',
                  );
                }
              },
              child: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );
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
    final endpoint = TextEditingController(text: c.apiUrl ?? ''),
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
