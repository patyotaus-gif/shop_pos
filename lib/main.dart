import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/auto_print_service.dart';
import 'services/auto_print_worker.dart';
import 'services/bank_notification_service.dart';
import 'services/notification_service.dart';
import 'models/shop.dart';
import 'screens/dashboard_screen.dart';
import 'screens/kitchen_screen.dart';
import 'screens/login_screen.dart';
import 'screens/order_qr_screen.dart';
import 'screens/pos_screen.dart';
import 'screens/products_screen.dart';
import 'screens/sales_tools_screen.dart';
import 'screens/report_screen.dart';
import 'screens/debt_screen.dart';
import 'screens/product_form_screen.dart';
import 'screens/orders_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/user_switch_screen.dart';
import 'screens/staff_mode_screen.dart';
import 'screens/offline_cash_screen.dart';
import 'services/offline_service.dart';
import 'screens/restaurant_sales_screen.dart';
import 'services/entitlements.dart';
import 'services/order_service.dart';
import 'services/shop_service.dart';
import 'services/theme_service.dart';
import 'theme/pokpok_theme.dart';
import 'widgets/pokpok_launch_motion.dart';
import 'services/update_service.dart';
import 'widgets/subscription_gate.dart';
import 'widgets/update_prompt.dart';
import 'widgets/side_navigation_shell.dart';
import 'widgets/connection_status_banner.dart';
import 'widgets/cash_session_status_banner.dart';
import 'widgets/workspace_sections.dart';
import 'widgets/recoverable_auth_builder.dart';
import 'widgets/app_viewport.dart';

// Default to light — Pokpok is a light-brand design and does not follow
// the device's system dark setting. Dark is opt-in (Settings), persisted
// via ThemeService and loaded at startup.
final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.light);

@pragma('vm:entry-point')
void autoPrintMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    await initializeDateFormatting('th_TH', null);
    final config = Map<String, dynamic>.from(
        await AutoPrintService.channel.invokeMapMethod('configuration') ?? {});
    await AutoPrintWorker(config).start();
  } catch (_) {
    await AutoPrintService.channel.invokeMethod<void>(
        'status', {'text': 'เริ่มคิวไม่สำเร็จ กรุณาเปิดแอพแล้วเริ่มใหม่'});
    await AutoPrintService.channel.invokeMethod<void>('stop');
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ShopPosApp());
}

Future<void> _initializeApp() async {
  await initializeDateFormatting('th_TH', null);
  themeNotifier.value = await ThemeService.load();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
      .timeout(const Duration(seconds: 15));
  // App Check (monitoring) — attests the app to Firebase backends so we
  // can later enforce that requests come from the real app. Release uses
  // Play Integrity / App Attest; debug builds use the debug provider.
  // Wrapped so an attestation hiccup never blocks startup.
  try {
    await FirebaseAppCheck.instance.activate(
      androidProvider:
          kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
      appleProvider: kDebugMode ? AppleProvider.debug : AppleProvider.appAttest,
    );
  } catch (_) {}
  await NotificationService.init().timeout(const Duration(seconds: 10));
  // Subscribe to bank notifications (Android only; no-op elsewhere).
  // Does not request permission — user enables that explicitly from
  // settings — but if it's already granted we start matching right away.
  await BankNotificationService.init().timeout(const Duration(seconds: 5));
  OfflineService.start();
}

class _BootErrorScreen extends StatelessWidget {
  const _BootErrorScreen({required this.message, required this.stack});
  final String message;
  final String stack;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Pokpok POS — startup failed',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(height: 12),
              SelectableText(message),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(
                    stack,
                    style: const TextStyle(fontSize: 11, fontFamily: 'Courier'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ShopPosApp extends StatefulWidget {
  const ShopPosApp({super.key, this.initialize = _initializeApp});
  final Future<void> Function() initialize;

  @override
  State<ShopPosApp> createState() => _ShopPosAppState();
}

class _ShopPosAppState extends State<ShopPosApp> {
  late final _initialization = Future<void>.sync(widget.initialize);

  Route<void> _rootRoute() => MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/'),
        builder: (_) => _BootHome(initialization: _initialization),
      );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, mode, _) => MaterialApp(
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('th'), Locale('en')],
        locale: const Locale('th'),
        title: 'Shop POS',
        debugShowCheckedModeBanner: false,
        themeMode: mode,
        theme: PokpokTheme.light(),
        darkTheme: PokpokTheme.dark(),
        builder: (context, child) => AppViewport(
          child: PokpokLaunchMotion(child: child ?? const SizedBox.shrink()),
        ),
        // Always enter through initialization and account selection on cold start.
        // Internal navigation can still open named routes after owner sign-in.
        onGenerateInitialRoutes: (_) => [_rootRoute()],
        onGenerateRoute: (settings) {
          if (settings.name == '/') return _rootRoute();
          if (settings.name == '/product-form' &&
              AuthService.ownerUnlocked &&
              !AuthService.isStaff &&
              AuthService.currentUser != null) {
            final barcode = settings.arguments as String?;
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => ProductFormScreen(initialBarcode: barcode),
            );
          }
          return null;
        },
      ),
    );
  }
}

class _BootHome extends StatelessWidget {
  const _BootHome({required this.initialization});
  final Future<void> initialization;

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
        future: initialization,
        builder: (context, boot) {
          if (boot.hasError) {
            return _BootErrorScreen(
                message: '${boot.error}', stack: '${boot.stackTrace}');
          }
          if (boot.connectionState != ConnectionState.done) {
            return const _StartingScreen();
          }
          return RecoverableAuthBuilder<User?>(
            streamFactory: () => AuthService.authStateStream,
            builder: (context, snap, retry) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const _StartingScreen();
              }
              if (snap.hasError) {
                return Scaffold(
                    body: Center(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(AuthService.sessionErrorMessage(snap.error)),
                  FilledButton.icon(
                      onPressed: retry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('ลองตรวจสิทธิ์อีกครั้ง')),
                  const OfflineEntryButton(),
                  TextButton(
                      onPressed: AuthService.signOut,
                      child: const Text('ออกจากระบบ')),
                ])));
              }
              if (snap.data == null) return const LoginScreen();
              // Load the founder custom claim for an already-signed-in user (app
              // relaunch); signIn() covers the fresh-login path. Fire-and-forget —
              // UI gates on the cached value once it resolves.
              AuthService.refreshFounderClaim();
              if (!AuthService.isStaff && !AuthService.ownerUnlocked) {
                return UserSwitchScreen(key: ValueKey(snap.data!.uid));
              }
              return AuthService.isStaff
                  ? StaffModeScreen(key: ValueKey(snap.data!.uid))
                  : SubscriptionGate(
                      child: MainShell(key: ValueKey(snap.data!.uid)));
            },
          );
        },
      );
}

class _StartingScreen extends StatelessWidget {
  const _StartingScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: MediaQuery.disableAnimationsOf(context)
              ? const Text('กำลังเปิดแอป')
              : const CircularProgressIndicator(semanticsLabel: 'กำลังเปิดแอป'),
        ),
      );
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  String _selectedLabel = 'ขาย';

  @override
  void initState() {
    super.initState();
    // Closed-distribution Android update check, once per launch. Silent on
    // failure / when already current / on iOS (TestFlight handles those).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final info = await UpdateService.checkForUpdate();
      if (info != null && mounted) showUpdateDialog(context, info);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Watch the shop doc so the nav reshapes immediately if the owner's
    // shop type ever changes (today only support can change it, but the
    // reactive shape keeps the door open for a self-serve toggle later).
    return StreamBuilder<Shop?>(
      stream: ShopService.watchCurrentShop(),
      builder: (context, shopSnap) {
        // Gate restaurant screens on tier — the single source of truth,
        // consistent with the QR screen + Entitlements. (Gating on the
        // shopType field let a console-upgraded shop keep shopType="retail"
        // and never see Tables/Kitchen.)
        final tier = shopSnap.data?.tier ?? ShopTier.full;
        final shopType = shopSnap.data?.shopType ?? ShopType.retail;
        final hasTables = Entitlements.canUseTables(tier, shopType);
        // Solo tier doesn't include the customer DB / debts feature, so
        // the ลูกค้าเครดิต tab is hidden for them. Tap on the upgrade
        // surfaces in Settings nudges them to Lite if they want it back.
        final showDebts = Entitlements.canUseCustomerDb(tier);

        return StreamBuilder<int>(
          stream: OrderService.watchNewOrders(),
          builder: (context, snap) {
            final newCount = snap.data ?? 0;

            // Daily actions first, followed by the remaining pages in the sidebar.
            final primaryTabs = <AppNavigationItem>[
              AppNavigationItem(
                screen: hasTables
                    ? const RestaurantSalesScreen()
                    : PosScreen(isFoodMenu: shopType == ShopType.restaurant),
                icon: hasTables
                    ? Icons.table_restaurant_outlined
                    : Icons.point_of_sale_outlined,
                selectedIcon:
                    hasTables ? Icons.table_restaurant : Icons.point_of_sale,
                label: 'ขาย',
              ),
              AppNavigationItem(
                screen: showDebts
                    ? WorkspaceSections(
                        labels: const ['ออเดอร์', 'ลูกค้าเครดิต'],
                        pages: [const OrdersScreen(), const DebtScreen()])
                    : const OrdersScreen(),
                icon: Icons.shopping_bag_outlined,
                selectedIcon: Icons.shopping_bag,
                label: 'ออเดอร์',
                badgeCount: newCount,
              ),
              const AppNavigationItem(
                screen: ProductsScreen(),
                icon: Icons.inventory_2_outlined,
                selectedIcon: Icons.inventory_2,
                label: 'สินค้า',
              ),
              const AppNavigationItem(
                screen: WorkspaceSections(
                    labels: ['ภาพรวม', 'รายงานยอดขาย'],
                    pages: [DashboardScreen(), ReportScreen()]),
                icon: Icons.bar_chart_outlined,
                selectedIcon: Icons.bar_chart,
                label: 'รายงาน',
              ),
            ];
            final moreTabs = <AppNavigationItem>[
              AppNavigationItem(
                screen: SalesToolsScreen(shopType: shopType),
                icon: Icons.local_offer_outlined,
                selectedIcon: Icons.local_offer,
                label: 'เครื่องมือส่งเสริมการขาย',
              ),
              if (hasTables)
                const AppNavigationItem(
                  screen: KitchenScreen(),
                  icon: Icons.soup_kitchen_outlined,
                  selectedIcon: Icons.soup_kitchen,
                  label: 'ครัว',
                ),
              const AppNavigationItem(
                screen: ChatScreen(),
                icon: Icons.auto_awesome_outlined,
                selectedIcon: Icons.auto_awesome,
                label: 'ผู้ช่วยร้าน',
              ),
              AppNavigationItem(
                screen: OrderQrScreen(shopType: shopType),
                icon: Icons.qr_code_2_outlined,
                selectedIcon: Icons.qr_code_2,
                label: shopType == ShopType.retail
                    ? 'ลิงก์และ QR สั่งสินค้า'
                    : 'QR สั่งอาหาร',
              ),
              const AppNavigationItem(
                screen: SettingsScreen(),
                icon: Icons.settings_outlined,
                selectedIcon: Icons.settings,
                label: 'ตั้งค่า',
              ),
            ];
            final tabs = [...primaryTabs, ...moreTabs];
            // Match the page by identity when tier changes reorder the menu.
            final selected =
                tabs.indexWhere((tab) => tab.label == _selectedLabel);
            final safeIndex = selected < 0 ? 0 : selected;
            return SideNavigationShell(
              items: tabs,
              statusBanner:
                  const Column(mainAxisSize: MainAxisSize.min, children: [
                CashSessionStatusBanner(),
                ConnectionStatusBanner(),
              ]),
              selectedIndex: safeIndex,
              onSelected: (index) =>
                  setState(() => _selectedLabel = tabs[index].label),
            );
          },
        );
      },
    );
  }
}
