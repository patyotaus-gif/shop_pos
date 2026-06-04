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
import 'widgets/subscription_gate.dart';

final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Render the splash immediately so we know the Flutter engine booted —
  // a frozen white screen on iOS first launch usually means main() is
  // blocked on an await before runApp ever runs.
  runApp(const _BootingApp());

  try {
    await initializeDateFormatting('th_TH', null);
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
        .timeout(const Duration(seconds: 15));
    await NotificationService.init().timeout(const Duration(seconds: 10));
    // Subscribe to bank notifications (Android only; no-op elsewhere).
    // Does not request permission — user enables that explicitly from
    // settings — but if it's already granted we start matching right away.
    await BankNotificationService.init().timeout(const Duration(seconds: 5));
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
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7A1F2B),
          brightness: Brightness.dark,
        ),
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const cream = Color(0xFFF5F1EC);
    const textDark = Color(0xFF1F1A1B);

    return Scaffold(
      backgroundColor: cream,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _anim,
              builder: (_, __) => Transform.scale(
                scale: 0.96 + _anim.value * 0.06,
                child: const SizedBox(
                  width: 110,
                  height: 110,
                  child: CustomPaint(painter: _MortarMarkPainter()),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'pokpok',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w300,
                color: textDark,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Brand mark — burgundy mortar + pestle, geometry mirrored from
/// assets/brand/01-mark-burgundy.svg (100×100 viewport).
class _MortarMarkPainter extends CustomPainter {
  const _MortarMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const burgundy = Color(0xFF7A1F2B);
    const cream = Color(0xFFF5F1EC);
    final s = size.width / 100;
    final fill = Paint()..color = burgundy;
    final stroke = Paint()
      ..color = burgundy
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2 * s;

    // Bowl — bottom half of an ellipse (cx 50, cy 56, rx 36, ry 32)
    final bowlRect = Rect.fromCenter(
      center: Offset(50 * s, 56 * s),
      width: 72 * s,
      height: 64 * s,
    );
    canvas.drawArc(bowlRect, 0, math.pi, true, fill);

    // Pestle — rounded pill from y=6 to y=48, x≈45.5–54.5, with the
    // accent dot near its lower end.
    final pestleRect = Rect.fromLTWH(45.5 * s, 6 * s, 9 * s, 42 * s);
    canvas.drawRRect(
      RRect.fromRectAndRadius(pestleRect, Radius.circular(4.5 * s)),
      fill,
    );

    // Base shelf rect (x 40, y 90, w 20, h 3)
    final baseRect = Rect.fromLTWH(40 * s, 90 * s, 20 * s, 3 * s);
    canvas.drawRRect(
      RRect.fromRectAndRadius(baseRect, Radius.circular(1.5 * s)),
      fill,
    );

    // Base line under shelf (x 30→70, y 90)
    canvas.drawLine(Offset(30 * s, 90 * s), Offset(70 * s, 90 * s), stroke);

    // Accent dot on the pestle (cream cut-out near its lower end).
    canvas.drawCircle(Offset(50 * s, 41 * s), 3.4 * s, Paint()..color = cream);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

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
