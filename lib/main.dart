import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/bank_notification_service.dart';
import 'services/notification_service.dart';
import 'models/shop.dart';
import 'screens/dashboard_screen.dart';
import 'screens/kitchen_screen.dart';
import 'screens/login_screen.dart';
import 'screens/pos_screen.dart';
import 'screens/products_screen.dart';
import 'screens/report_screen.dart';
import 'screens/debt_screen.dart';
import 'screens/product_form_screen.dart';
import 'screens/orders_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/tables_screen.dart';
import 'services/entitlements.dart';
import 'services/order_service.dart';
import 'services/shop_service.dart';
import 'services/update_service.dart';
import 'widgets/subscription_gate.dart';
import 'widgets/update_prompt.dart';

final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

/// Brand typeface, bundled in assets and declared in pubspec.yaml. Matches
/// the pok-pok.app website so the app and web share one identity.
const _brandFont = 'IBM Plex Sans Thai';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Render the splash immediately so we know the Flutter engine booted —
  // a frozen white screen on iOS first launch usually means main() is
  // blocked on an await before runApp ever runs.
  runApp(const _BootingApp());

  // Hold the splash for a minimum beat so the mortar-pounding animation
  // plays in full even on fast cold starts. Init runs concurrently
  // underneath; we wait on whichever finishes last.
  final minSplash = Future<void>.delayed(const Duration(seconds: 3));

  try {
    await initializeDateFormatting('th_TH', null);
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
        .timeout(const Duration(seconds: 15));
    await NotificationService.init().timeout(const Duration(seconds: 10));
    // Subscribe to bank notifications (Android only; no-op elsewhere).
    // Does not request permission — user enables that explicitly from
    // settings — but if it's already granted we start matching right away.
    await BankNotificationService.init().timeout(const Duration(seconds: 5));
    await minSplash;
    runApp(const ShopPosApp());
  } catch (e, st) {
    runApp(_BootErrorApp(message: '$e', stack: '$st'));
  }
}

class _BootingApp extends StatelessWidget {
  const _BootingApp();
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _PokpokSplash(),
    );
  }
}

class _BootErrorApp extends StatelessWidget {
  const _BootErrorApp({required this.message, required this.stack});
  final String message;
  final String stack;
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF5F1EC),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Pokpok POS — startup failed',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF7A1F2B)),
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
      ),
    );
  }
}

class ShopPosApp extends StatelessWidget {
  const ShopPosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, mode, _) => MaterialApp(
      title: 'Shop POS',
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7A1F2B),
          brightness: Brightness.light,
        ),
        fontFamily: _brandFont,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7A1F2B),
          brightness: Brightness.dark,
        ),
        fontFamily: _brandFont,
        useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
        stream: AuthService.authStateStream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const _PokpokSplash();
          }
          if (snap.data == null) return const LoginScreen();
          return const SubscriptionGate(child: MainShell());
        },
      ),
      onGenerateRoute: (settings) {
        if (settings.name == '/product-form') {
          final barcode = settings.arguments as String?;
          return MaterialPageRoute(
            builder: (_) => ProductFormScreen(initialBarcode: barcode),
          );
        }
        return null;
      },
    ),
    );
  }
}

class _PokpokSplash extends StatefulWidget {
  const _PokpokSplash();
  @override
  State<_PokpokSplash> createState() => _PokpokSplashState();
}

class _PokpokSplashState extends State<_PokpokSplash>
    with TickerProviderStateMixin {
  late final AnimationController _loop; // 2s mortar-pounding loop
  late final AnimationController _intro; // one-shot wordmark fade-in

  @override
  void initState() {
    super.initState();
    _loop = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
  }

  @override
  void dispose() {
    _loop.dispose();
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const burgundy = Color(0xFF7A1F2B);
    const cream = Color(0xFFF5F1EC);

    return Scaffold(
      backgroundColor: burgundy,
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 200,
                  height: 200,
                  child: AnimatedBuilder(
                    animation: _loop,
                    builder: (_, __) =>
                        CustomPaint(painter: _SplashMarkPainter(_loop.value)),
                  ),
                ),
                const SizedBox(height: 22),
                FadeTransition(
                  opacity:
                      CurvedAnimation(parent: _intro, curve: Curves.easeOut),
                  child: Column(
                    children: [
                      const Text(
                        'pokpok',
                        style: TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w300,
                          color: cream,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'POINT OF SALE',
                        style: TextStyle(
                          fontSize: 12,
                          color: cream.withValues(alpha: 0.85),
                          letterSpacing: 5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Three pulsing loader dots near the bottom edge.
          Positioned(
            left: 0,
            right: 0,
            bottom: 56,
            child: AnimatedBuilder(
              animation: _loop,
              builder: (_, __) => Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) {
                  final phase = (_loop.value + i * 0.12) % 1.0;
                  final o = (0.25 +
                          0.75 * (0.5 + 0.5 * math.sin(phase * 2 * math.pi)))
                      .clamp(0.0, 1.0);
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cream.withValues(alpha: o),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated splash mark — a cream mortar + pestle on burgundy. The pestle
/// pounds twice into the bowl per 2s loop, the bowl squashes on impact and
/// two ripples pulse out. Geometry + keyframes ported from the
/// pokpok-splash reference (200×200 viewport).
class _SplashMarkPainter extends CustomPainter {
  const _SplashMarkPainter(this.t);

  /// Loop progress 0..1.
  final double t;

  /// Piecewise-linear keyframe sampler — [stops] ascending in 0..1.
  static double _kf(double t, List<double> stops, List<double> values) {
    if (t <= stops.first) return values.first;
    if (t >= stops.last) return values.last;
    for (var i = 0; i < stops.length - 1; i++) {
      if (t <= stops[i + 1]) {
        final f = (t - stops[i]) / (stops[i + 1] - stops[i]);
        return values[i] + (values[i + 1] - values[i]) * f;
      }
    }
    return values.last;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const cream = Color(0xFFF5F1EC);
    canvas.scale(size.width / 200);
    final fill = Paint()..color = cream;

    // ── Ripple (two pulses per loop, behind the bowl) ──
    final rScale = _kf(
        t, [0, .16, .30, .35, .45, 1.0], [.35, .35, 1.5, .35, 1.4, 1.4]);
    final rOpacity = _kf(t, [0, .16, .20, .30, .35, .45, 1.0],
        [0, 0, .5, 0, .45, 0, 0]);
    if (rOpacity > 0.01) {
      canvas.drawCircle(
        const Offset(100, 120),
        26 * rScale,
        Paint()
          ..color = cream.withValues(alpha: rOpacity.clamp(0.0, 1.0))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }

    // ── Bowl (squashes around its base on each impact) ──
    final bScaleX = _kf(t, [0, .10, .19, .25, .35, .40, 1.0],
        [1, 1, 1.04, 1, 1.025, 1, 1]);
    final bScaleY = _kf(
        t, [0, .10, .19, .25, .35, .40, 1.0], [1, 1, .94, 1, .97, 1, 1]);
    canvas.save();
    canvas.translate(100, 162);
    canvas.scale(bScaleX, bScaleY);
    canvas.translate(-100, -162);
    canvas.drawArc(
      Rect.fromCenter(center: const Offset(100, 120), width: 90, height: 84),
      0,
      math.pi,
      true,
      fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(88, 166, 24, 5), const Radius.circular(2.5)),
      fill,
    );
    canvas.drawLine(
      const Offset(72, 166),
      const Offset(128, 166),
      Paint()
        ..color = cream
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();

    // ── Pestle (pounds vertically into the bowl) ──
    final dy = _kf(t, [0, .10, .19, .26, .35, .41, .48, .70, 1.0],
        [-52, -52, 0, -22, 0, -9, 0, 0, -52]);
    canvas.save();
    canvas.translate(0, dy);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(92, 52, 16, 68), const Radius.circular(8)),
      fill,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SplashMarkPainter old) => old.t != t;
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

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
        final isRestaurant =
            shopSnap.data?.shopType == ShopType.restaurant;
        // Solo tier doesn't include the customer DB / debts feature, so
        // the ลูกหนี้ tab is hidden for them. Tap on the upgrade
        // surfaces in Settings nudges them to Lite if they want it back.
        final tier = shopSnap.data?.tier ?? ShopTier.full;
        final showDebts = Entitlements.canUseCustomerDb(tier);

        return StreamBuilder<int>(
          stream: OrderService.watchNewOrders(),
          builder: (context, snap) {
            final newCount = snap.data ?? 0;

            // Build screens + destinations together so indices stay aligned.
            // Restaurant mode swaps the POS tab for Tables (entry point of
            // the table-based flow) and adds Kitchen near the end.
            final tabs = <_NavTab>[
              const _NavTab(
                screen: DashboardScreen(),
                icon: Icons.dashboard_outlined,
                selectedIcon: Icons.dashboard,
                label: 'ภาพรวม',
              ),
              if (isRestaurant)
                const _NavTab(
                  screen: TablesScreen(),
                  icon: Icons.table_restaurant_outlined,
                  selectedIcon: Icons.table_restaurant,
                  label: 'โต๊ะ',
                )
              else
                const _NavTab(
                  screen: PosScreen(),
                  icon: Icons.point_of_sale_outlined,
                  selectedIcon: Icons.point_of_sale,
                  label: 'ขายสินค้า',
                ),
              const _NavTab(
                screen: ProductsScreen(),
                icon: Icons.inventory_2_outlined,
                selectedIcon: Icons.inventory_2,
                label: 'สินค้า',
              ),
              const _NavTab(
                screen: ReportScreen(),
                icon: Icons.bar_chart_outlined,
                selectedIcon: Icons.bar_chart,
                label: 'รายงาน',
              ),
              if (showDebts)
                const _NavTab(
                  screen: DebtScreen(),
                  icon: Icons.people_outline,
                  selectedIcon: Icons.people,
                  label: 'ลูกหนี้',
                ),
              _NavTab(
                screen: const OrdersScreen(),
                icon: Icons.shopping_bag_outlined,
                selectedIcon: Icons.shopping_bag,
                label: 'Orders',
                badgeCount: newCount,
              ),
              if (isRestaurant)
                const _NavTab(
                  screen: KitchenScreen(),
                  icon: Icons.soup_kitchen_outlined,
                  selectedIcon: Icons.soup_kitchen,
                  label: 'ครัว',
                ),
              // Marketplace ("สั่งของ") is reached from a Dashboard card,
              // not the bottom nav — the bar is already at its tab budget
              // (8-9), and the GTM plan wants marketplace soft-launched
              // rather than front-and-center for every shop on day one.
              const _NavTab(
                screen: ChatScreen(),
                icon: Icons.auto_awesome_outlined,
                selectedIcon: Icons.auto_awesome,
                label: 'AI',
              ),
              const _NavTab(
                screen: SettingsScreen(),
                icon: Icons.settings_outlined,
                selectedIcon: Icons.settings,
                label: 'ตั้งค่า',
              ),
            ];

            // Clamp in case shop type flipped and the previously selected
            // index is now out of range.
            final safeIndex = _index.clamp(0, tabs.length - 1);

            return Scaffold(
              body: IndexedStack(
                index: safeIndex,
                children: tabs.map((t) => t.screen).toList(),
              ),
              bottomNavigationBar: NavigationBar(
                selectedIndex: safeIndex,
                onDestinationSelected: (i) => setState(() => _index = i),
                // Tighter sizing — 8 destinations on a phone-width screen
                // would otherwise overlap labels (especially on Android,
                // whose default Thai font is wider than iOS). Restaurant
                // mode adds a 9th, so we keep the same compact metrics.
                height: 64,
                labelTextStyle: WidgetStateProperty.resolveWith((states) {
                  final selected = states.contains(WidgetState.selected);
                  return TextStyle(
                    fontSize: 10,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500,
                  );
                }),
                destinations:
                    tabs.map((t) => t.toDestination()).toList(),
              ),
            );
          },
        );
      },
    );
  }
}

/// One bottom-nav entry. Pulled out so the conditional restaurant-vs-retail
/// list stays readable in `_MainShellState.build` and so screens + their
/// matching `NavigationDestination` can't drift out of sync.
class _NavTab {
  const _NavTab({
    required this.screen,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badgeCount = 0,
  });

  final Widget screen;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int badgeCount;

  NavigationDestination toDestination() {
    if (badgeCount > 0) {
      return NavigationDestination(
        icon: Badge(label: Text('$badgeCount'), child: Icon(icon)),
        selectedIcon:
            Badge(label: Text('$badgeCount'), child: Icon(selectedIcon)),
        label: label,
      );
    }
    return NavigationDestination(
      icon: Icon(icon),
      selectedIcon: Icon(selectedIcon),
      label: label,
    );
  }
}
