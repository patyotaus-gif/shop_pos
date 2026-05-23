import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'screens/pos_screen.dart';
import 'screens/products_screen.dart';
import 'screens/report_screen.dart';
import 'screens/debt_screen.dart';
import 'screens/product_form_screen.dart';
import 'screens/orders_screen.dart';
import 'screens/chat_screen.dart';
import 'services/groq_service.dart';
import 'screens/settings_screen.dart';
import 'services/order_service.dart';
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
    const groqKey = String.fromEnvironment('GROQ_API_KEY');
    if (groqKey.isNotEmpty) {
      GroqService.setApiKey(groqKey);
    }
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
        backgroundColor: const Color(0xFFFFFBF7),
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
                      color: Color(0xFFBE123C)),
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
          seedColor: const Color(0xFF1E40AF),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E40AF),
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
    const ruby = Color(0xFFBE123C);
    const slate = Color(0xFF1E293B);
    const cream = Color(0xFFFFFBF7);

    return Scaffold(
      backgroundColor: cream,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _anim,
              builder: (_, __) {
                final h1 = 28.0 + _anim.value * 28.0;
                final h2 = 56.0 - _anim.value * 28.0;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      width: 18,
                      height: h1,
                      decoration: BoxDecoration(
                        color: ruby,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 18,
                      height: h2,
                      decoration: BoxDecoration(
                        color: slate,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            const Text(
              'Pokpok',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: slate,
                letterSpacing: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _screens = [
    DashboardScreen(),
    PosScreen(),
    ProductsScreen(),
    ReportScreen(),
    DebtScreen(),
    OrdersScreen(),
    ChatScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: OrderService.watchNewOrders(),
      builder: (context, AsyncSnapshot<int> snap) {
        final newCount = snap.data ?? 0;
        return Scaffold(
          body: IndexedStack(index: _index, children: _screens),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: 'ภาพรวม',
              ),
              const NavigationDestination(
                icon: Icon(Icons.point_of_sale_outlined),
                selectedIcon: Icon(Icons.point_of_sale),
                label: 'ขายสินค้า',
              ),
              const NavigationDestination(
                icon: Icon(Icons.inventory_2_outlined),
                selectedIcon: Icon(Icons.inventory_2),
                label: 'สินค้า',
              ),
              const NavigationDestination(
                icon: Icon(Icons.bar_chart_outlined),
                selectedIcon: Icon(Icons.bar_chart),
                label: 'รายงาน',
              ),
              const NavigationDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people),
                label: 'ลูกหนี้',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: newCount > 0,
                  label: Text('$newCount'),
                  child: const Icon(Icons.shopping_bag_outlined),
                ),
                selectedIcon: Badge(
                  isLabelVisible: newCount > 0,
                  label: Text('$newCount'),
                  child: const Icon(Icons.shopping_bag),
                ),
                label: 'Orders',
              ),
              const NavigationDestination(
                icon: Icon(Icons.auto_awesome_outlined),
                selectedIcon: Icon(Icons.auto_awesome),
                label: 'AI',
              ),
              const NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'ตั้งค่า',
              ),
            ],
          ),
        );
      },
    );
  }
}
