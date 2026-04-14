//Julianne Marie M. Casia

import 'dart:async';
import 'package:exam/pages/dashboard_screen.dart';
import 'package:exam/pages/details.dart';
import 'package:exam/pages/my_account_screen.dart';
import 'package:exam/services/web_theme_storage.dart' as web_theme_storage;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String _themePrefKey = 'isDarkMode';
const String _routePrefKey = 'lastRoute';

const String _authRoute = '/auth';
const String _dashboardRoute = '/dashboard';
const String _settingsRoute = '/settings';
const String _detailsRoute = '/details';
const String _myAccountRoute = '/my-account';

const String _supabaseUrl = 'https://uimpwcruncvihxxbgdxp.supabase.co';
const String _supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVpbXB3Y3J1bmN2aWh4eGJnZHhwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ1MjQwMTIsImV4cCI6MjA5MDEwMDAxMn0.P17YEAHdscL3WQmauAwkQqEvZpim_MhQmwFsy_-2ETc';
const String _siteUrl = 'http://localhost:64026';
const Set<String> _allowedRoutes = {
  _authRoute,
  _dashboardRoute,
  _settingsRoute,
  _myAccountRoute,
};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseAnonKey);

  // Wait a moment for Supabase to restore session from storage
  await Future.delayed(const Duration(milliseconds: 100));

  final bootstrap = await _buildBootstrap(prefs);

  runApp(
    WasteCollectionApp(
      initialDarkMode: bootstrap.initialDarkMode,
      initialRoute: bootstrap.initialRoute,
      prefs: prefs,
    ),
  );
}

Future<_AppBootstrapData> _buildBootstrap(SharedPreferences prefs) async {
  final webThemeMode = web_theme_storage.readWebThemeMode();
  final isDarkMode = webThemeMode ?? (prefs.getBool(_themePrefKey) ?? false);

  final savedRoute = prefs.getString(_routePrefKey) ?? _authRoute;
  var initialRoute = _allowedRoutes.contains(savedRoute)
      ? savedRoute
      : _authRoute;

  final authIntentFromUrl = _readAuthIntentFromUrl();
  final client = Supabase.instance.client;
  var session = client.auth.currentSession;

  // Enforce fresh login on app relaunch. Keep session only when returning from OAuth callback.
  if (session != null && authIntentFromUrl == null) {
    await client.auth.signOut();
    session = null;
  }

  // If user is already authenticated (logged in before), automatically route to dashboard
  if (session != null) {
    // User is logged in - route to dashboard for automatic login
    initialRoute = _dashboardRoute;

    // If this is a Google signup redirect, tag user as admin
    if (authIntentFromUrl == 'signup') {
      await client.auth.updateUser(
        UserAttributes(data: {'role': 'admin', 'signup_method': 'google'}),
      );
    }
  } else {
    // No session - user must log in
    initialRoute = _authRoute;
  }

  return _AppBootstrapData(
    initialDarkMode: isDarkMode,
    initialRoute: initialRoute,
  );
}

String? _readAuthIntentFromUrl() {
  final intent = Uri.base.queryParameters['intent'];
  if (intent == 'signup' || intent == 'login') {
    return intent;
  }
  return null;
}

class _AppBootstrapData {
  const _AppBootstrapData({
    required this.initialDarkMode,
    required this.initialRoute,
  });

  final bool initialDarkMode;
  final String initialRoute;
}

class WasteCollectionApp extends StatefulWidget {
  const WasteCollectionApp({
    required this.initialDarkMode,
    required this.initialRoute,
    required this.prefs,
    super.key,
  });

  final bool initialDarkMode;
  final String initialRoute;
  final SharedPreferences prefs;

  @override
  State<WasteCollectionApp> createState() => _WasteCollectionAppState();
}

class _WasteCollectionAppState extends State<WasteCollectionApp>
    with WidgetsBindingObserver {
  late bool _isDarkMode;
  late String _currentRoute;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late StreamSubscription<AuthState> _authStateSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isDarkMode = widget.initialDarkMode;
    _currentRoute = widget.initialRoute;

    // Listen to auth state changes
    _authStateSubscription = Supabase.instance.client.auth.onAuthStateChange
        .listen((data) {
          final session = data.session;
          if (session == null && _currentRoute != _authRoute) {
            // User logged out or session expired - redirect to auth screen
            _navigatorKey.currentState?.pushNamedAndRemoveUntil(
              _authRoute,
              (route) => false,
            );
            _currentRoute = _authRoute;
          } else if (session != null && _currentRoute == _authRoute) {
            // User just logged in - redirect to dashboard
            _navigatorKey.currentState?.pushNamedAndRemoveUntil(
              _dashboardRoute,
              (route) => false,
            );
            _currentRoute = _dashboardRoute;
          }
        });
  }

  @override
  void dispose() {
    _authStateSubscription.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_persistAppState());
    }
  }

  Future<void> _persistAppState() async {
    web_theme_storage.writeWebThemeMode(_isDarkMode);
    await widget.prefs.setBool(_themePrefKey, _isDarkMode);
    await widget.prefs.setString(_routePrefKey, _currentRoute);
  }

  Future<void> _saveRoute(String route) async {
    if (!_allowedRoutes.contains(route)) {
      return;
    }
    _currentRoute = route;
    await _persistAppState();
  }

  Future<void> _setThemeMode(bool isDarkMode) async {
    setState(() {
      _isDarkMode = isDarkMode;
    });
    await _persistAppState();
  }

  Future<void> _startGoogleAuth({required bool isSignUp}) async {
    final intent = isSignUp ? 'signup' : 'login';

    await Supabase.instance.client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: '$_siteUrl/?intent=$intent',
      queryParams: const {'prompt': 'select_account'},
    );
  }

  Future<void> _loginWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final response = await Supabase.instance.client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );

    final user = response.user;
    if (user == null) {
      throw const AuthException('Login failed. Please check your credentials.');
    }

    await _saveRoute(_dashboardRoute);
    _navigatorKey.currentState?.pushNamedAndRemoveUntil(
      _dashboardRoute,
      (route) => false,
    );
  }

  Future<void> _logoutAndShowAuth() async {
    await Supabase.instance.client.auth.signOut();
    await _saveRoute(_authRoute);
    _navigatorKey.currentState?.pushNamedAndRemoveUntil(
      _authRoute,
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Garbage Waste Collection',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      initialRoute: widget.initialRoute,
      navigatorObservers: [
        _RoutePersistenceObserver(onRouteChanged: _saveRoute),
      ],
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      routes: {
        _authRoute: (_) => AuthScreen(
          onGoogleAuthRequested: _startGoogleAuth,
          onEmailLoginRequested: _loginWithEmailAndPassword,
          prefs: widget.prefs,
        ),
        _dashboardRoute: (_) => DashboardScreen(
          onLogout: () {
            unawaited(_logoutAndShowAuth());
          },
        ),
        _settingsRoute: (_) => SettingsScreen(
          isDarkMode: _isDarkMode,
          onThemeChanged: _setThemeMode,
          onLogout: () {
            unawaited(_logoutAndShowAuth());
          },
        ),
        _detailsRoute: (context) {
          final args =
              ModalRoute.of(context)?.settings.arguments
                  as Map<String, dynamic>?;
          final barangayId = args?['barangayId'] as int? ?? 0;
          final barangayName =
              args?['barangayName'] as String? ?? 'Barangay details';
          final district = args?['district'] as String? ?? '';
          final city = args?['city'] as String? ?? 'Davao City';

          return DetailsScreen(
            barangayId: barangayId,
            barangayName: barangayName,
            district: district,
            city: city,
            onLogout: () {
              unawaited(_logoutAndShowAuth());
            },
          );
        },
        _myAccountRoute: (_) => const MyAccountScreen(),
      },
      onUnknownRoute: (_) => MaterialPageRoute<void>(
        builder: (_) => AuthScreen(
          onGoogleAuthRequested: _startGoogleAuth,
          onEmailLoginRequested: _loginWithEmailAndPassword,
          prefs: widget.prefs,
        ),
        settings: const RouteSettings(name: _authRoute),
      ),
    );
  }
}

class _RoutePersistenceObserver extends NavigatorObserver {
  _RoutePersistenceObserver({required this.onRouteChanged});

  final ValueChanged<String> onRouteChanged;

  void _storeRoute(Route<dynamic>? route) {
    final routeName = route?.settings.name;
    if (routeName != null && routeName.isNotEmpty) {
      onRouteChanged(routeName);
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _storeRoute(route);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _storeRoute(previousRoute);
    super.didPop(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _storeRoute(newRoute);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}

ThemeData _buildLightTheme() {
  const seed = Color(0xFF131F16);
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: Brightness.light,
  );

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFEDF5EF),
    fontFamily: 'Segoe UI',
    useMaterial3: true,
    textTheme: ThemeData.light().textTheme.copyWith(
      headlineSmall: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
      titleLarge: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
      titleMedium: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      bodyMedium: const TextStyle(fontSize: 14.5, height: 1.35),
      labelLarge: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: const Color(0xFFF6FBF7),
      foregroundColor: scheme.onSurface,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 21,
        fontWeight: FontWeight.w800,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: const Color(0xFFF7FCF8),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 46),
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      side: BorderSide(color: scheme.outlineVariant),
      backgroundColor: const Color(0xFFDDEDE0),
      labelStyle: TextStyle(
        color: scheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      backgroundColor: const Color(0xFF131F16),
      contentTextStyle: const TextStyle(color: Colors.white),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF8FCF9),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: _inputBorder(scheme.outlineVariant),
      enabledBorder: _inputBorder(scheme.outlineVariant),
      focusedBorder: _inputBorder(seed, width: 1.6),
    ),
  );
}

ThemeData _buildDarkTheme() {
  const seed = Color(0xFF131F16);
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: Brightness.dark,
  );

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF090D0A),
    fontFamily: 'Segoe UI',
    useMaterial3: true,
    textTheme: ThemeData.dark().textTheme.copyWith(
      headlineSmall: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
      titleLarge: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
      titleMedium: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      bodyMedium: const TextStyle(fontSize: 14.5, height: 1.35),
      labelLarge: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: const Color(0xFF0A0F0B),
      foregroundColor: scheme.onSurface,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 21,
        fontWeight: FontWeight.w800,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: const Color(0xFF111A14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 46),
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      side: BorderSide(color: scheme.outlineVariant),
      backgroundColor: const Color(0xFF1D2C22),
      labelStyle: TextStyle(
        color: scheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      backgroundColor: const Color(0xFF131F16),
      contentTextStyle: const TextStyle(color: Colors.white),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF17221A),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: _inputBorder(scheme.outlineVariant),
      enabledBorder: _inputBorder(scheme.outlineVariant),
      focusedBorder: _inputBorder(seed, width: 1.6),
    ),
  );
}

OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: color, width: width),
  );
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    required this.onGoogleAuthRequested,
    required this.onEmailLoginRequested,
    required this.prefs,
    super.key,
  });

  final Future<void> Function({required bool isSignUp}) onGoogleAuthRequested;
  final Future<void> Function({required String email, required String password})
  onEmailLoginRequested;
  final SharedPreferences prefs;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _loginFormKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleGoogleAuth() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await widget.onGoogleAuthRequested(isSignUp: !_isLogin);
    } on AuthException catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
      setState(() {
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to continue with Google authentication.'),
        ),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _handleEmailLogin() async {
    final form = _loginFormKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await widget.onEmailLoginRequested(
        email: _emailController.text,
        password: _passwordController.text,
      );
    } on AuthException catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
      setState(() {
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to log in with this account.')),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF050806),
              const Color(0xFF1F3A2A),
              const Color(0xFF070A08),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.recycling),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Garbage Waste Collection',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _isLogin
                              ? 'Log in using your email/password or continue with your previous Google account.'
                              : 'Sign up with Google to create your account in Supabase.',
                        ),
                        const SizedBox(height: 18),
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment<bool>(
                              value: true,
                              label: Text('Login Using Email'),
                              icon: Icon(Icons.login),
                            ),
                            ButtonSegment<bool>(
                              value: false,
                              label: Text('Login with Google'),
                              icon: Icon(Icons.app_registration),
                            ),
                          ],
                          selected: {_isLogin},
                          onSelectionChanged: (selection) {
                            setState(() {
                              _isLogin = selection.first;
                            });
                          },
                        ),
                        if (_isLogin) ...[
                          const SizedBox(height: 16),
                          Form(
                            key: _loginFormKey,
                            child: Column(
                              children: [
                                TextFormField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: const InputDecoration(
                                    labelText: 'Email',
                                    prefixIcon: Icon(Icons.email),
                                  ),
                                  validator: (value) {
                                    final text = value?.trim() ?? '';
                                    if (text.isEmpty || !text.contains('@')) {
                                      return 'Please enter a valid email.';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: _obscurePassword,
                                  decoration: InputDecoration(
                                    labelText: 'Password',
                                    prefixIcon: const Icon(Icons.lock),
                                    suffixIcon: IconButton(
                                      tooltip: _obscurePassword
                                          ? 'Show password'
                                          : 'Hide password',
                                      onPressed: () {
                                        setState(() {
                                          _obscurePassword = !_obscurePassword;
                                        });
                                      },
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility
                                            : Icons.visibility_off,
                                      ),
                                    ),
                                  ),
                                  validator: (value) {
                                    final text = value ?? '';
                                    if (text.isEmpty) {
                                      return 'Please enter your password.';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 14),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton(
                                    onPressed: _isLoading
                                        ? null
                                        : _handleEmailLogin,
                                    child: Text(
                                      _isLoading ? 'Signing in...' : 'Log In',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (!_isLogin) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _isLoading ? null : _handleGoogleAuth,
                              icon: const Icon(Icons.g_mobiledata),
                              label: Text(
                                _isLoading
                                    ? 'Redirecting...'
                                    : 'Sign Up with Google',
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
