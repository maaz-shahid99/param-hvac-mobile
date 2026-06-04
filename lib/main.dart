import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ble_service.dart';
import 'services/topology_service.dart';
import 'services/auth_service.dart';
import 'screens/home_page.dart';
import 'screens/member_home_page.dart';
import 'screens/login_page.dart';
import 'screens/splash_page.dart';
import 'screens/pending_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BLEService()),
        ChangeNotifierProvider(create: (_) => TopologyService()..load()),
        ChangeNotifierProvider(create: (_) => AuthService()..restore()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('isDarkMode') ?? true;
    setState(() {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
  }

  Future<void> _toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = _themeMode == ThemeMode.dark;
    await prefs.setBool('isDarkMode', !isDark);
    setState(() {
      _themeMode = isDark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Thread Commissioner',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: _AuthGate(onToggleTheme: _toggleTheme),
    );
  }
}

/// Routes between splash (restoring session), login (signed out) and the app
/// (signed in). On sign-in it binds the topology service to the cloud so the
/// rack layout syncs instead of living only on this phone.
class _AuthGate extends StatefulWidget {
  final VoidCallback onToggleTheme;
  const _AuthGate({required this.onToggleTheme});

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  AuthStatus _last = AuthStatus.unknown;

  void _onAuthChanged(AuthService auth, TopologyService topo) {
    if (auth.status == _last) return;
    _last = auth.status;
    if (auth.status == AuthStatus.signedIn) {
      topo.bindCloud(auth.api);
      topo.loadFromCloud();
    } else if (auth.status == AuthStatus.signedOut) {
      topo.bindCloud(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AuthService, TopologyService>(
      builder: (context, auth, topo, _) {
        // React to auth transitions without rebuilding loops.
        WidgetsBinding.instance.addPostFrameCallback((_) => _onAuthChanged(auth, topo));
        switch (auth.status) {
          case AuthStatus.unknown:
            return const SplashPage();
          case AuthStatus.signedOut:
            return const LoginPage();
          case AuthStatus.signedIn:
            // A member whose join request hasn't been approved waits here.
            if (auth.isPending) return const PendingPage();
            // Admins get the installer home; members get the monitoring home.
            return auth.isAdmin
                ? HomePage(onToggleTheme: widget.onToggleTheme)
                : MemberHomePage(onToggleTheme: widget.onToggleTheme);
        }
      },
    );
  }
}
