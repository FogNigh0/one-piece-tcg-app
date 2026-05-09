// lib/app/app.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/search/presentation/search_screen.dart';
import '../features/scanner/presentation/scanner_screen.dart';
import '../features/collection/presentation/collection_screen.dart';
import '../core/services/auth_service.dart';
import '../core/database/card_database.dart';
import '../core/services/sync_service.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/folders/presentation/shared_folder_screen.dart';

// ── Colores globales ────────────────────────────────────────────────────────
const Color kBlack = Color(0xFF0D0D0D);
const Color kSurface = Color(0xFF1A1A1A);
const Color kSurface2 = Color(0xFF222222);
const Color kBorder = Color(0xFF2E2E2E);
const Color kGold = Color(0xFFD4A843);

// ── Eventos globales ────────────────────────────────────────────────────────
class AppEvents {
  AppEvents._();

  // Colección: notifica cambios (agregar/borrar/mover cartas)
  static final collectionVersion = ValueNotifier<int>(0);
  static void notifyCollectionChanged() => collectionVersion.value++;

  // Carpetas: notifica cambios (crear/editar/borrar carpetas)
  static final _foldersCtrl = StreamController<void>.broadcast();
  static Stream<void> get onFoldersChanged => _foldersCtrl.stream;
  static void notifyFoldersChanged() => _foldersCtrl.add(null);

  // Navegación: usa Stream para que el mismo índice siempre dispare
  static final _navCtrl = StreamController<int>.broadcast();
  static Stream<int> get onNavigate => _navCtrl.stream;
  static void navigateTo(int index) => _navCtrl.add(index);

  // Login exitoso: notifica a AuthGate sin pasar callbacks
  static final _loginCtrl = StreamController<void>.broadcast();
  static Stream<void> get onLoginSuccess => _loginCtrl.stream;
  static void notifyLoginSuccess() => _loginCtrl.add(null);
}

// ── App principal ────────────────────────────────────────────────────────────
class OnePieceCardScannerApp extends StatefulWidget {
  const OnePieceCardScannerApp({super.key});

  @override
  State<OnePieceCardScannerApp> createState() => _OnePieceCardScannerAppState();
}

class _OnePieceCardScannerAppState extends State<OnePieceCardScannerApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    final appLinks = AppLinks();
    // Link inicial (app estaba cerrada)
    final initial = await appLinks.getInitialLink();
    if (initial != null) _handleLink(initial);
    // Links mientras la app está abierta
    _linkSub = appLinks.uriLinkStream.listen(_handleLink);
  }

  void _handleLink(Uri uri) {
    // opcardscanner://folder/{share_token}
    if (uri.scheme == 'opcardscanner' && uri.host == 'folder') {
      final token = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
      if (token != null && token.isNotEmpty) {
        _navigatorKey.currentState?.push(MaterialPageRoute(
          builder: (_) => SharedFolderScreen(shareToken: token),
        ));
      }
    }
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'One Piece Card Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.dark(
          primary: kGold,
          surface: kSurface,
          onSurface: Colors.white,
          background: kBlack,
        ),
        scaffoldBackgroundColor: kBlack,
        appBarTheme: const AppBarTheme(
          backgroundColor: kBlack,
          foregroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleTextStyle: TextStyle(
            color: kGold,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: kSurface,
          selectedItemColor: kGold,
          unselectedItemColor: Color(0xFF555555),
          type: BottomNavigationBarType.fixed,
          elevation: 8,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: kSurface2,
          hintStyle: const TextStyle(color: Color(0xFF555555)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kGold, width: 1.5),
          ),
          prefixIconColor: const Color(0xFF666666),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: kGold,
            foregroundColor: kBlack,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

// ── Shell con bottom nav ─────────────────────────────────────────────────────
class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;
  StreamSubscription<int>? _navSub;

  // Índices:  0=Home  1=Search  2=Scanner  3=Collection 4=profile
  static const _screens = [
    HomeScreen(),
    SearchScreen(),
    ScannerScreen(),
    CollectionScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Escucha navegación programática — siempre dispara aunque sea el mismo índice
    _navSub = AppEvents.onNavigate.listen((index) {
      if (mounted && index >= 0 && index < _screens.length) {
        setState(() => _currentIndex = index);
      }
    });
  }

  @override
  void dispose() {
    _navSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search_outlined),
            activeIcon: Icon(Icons.search),
            label: 'Buscar',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.document_scanner_outlined),
            activeIcon: Icon(Icons.document_scanner),
            label: 'Scanner',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.collections_bookmark_outlined),
            activeIcon: Icon(Icons.collections_bookmark),
            label: 'Colección',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}

// ── Auth Gate: decide si mostrar login o la app ──────────────────────────────
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _auth = AuthService();
  bool _checking = true;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final loggedIn = await _auth.isLoggedIn;
    if (loggedIn) {
      // Inicializa la BD para el usuario actual
      final user = await _auth.getCachedUser();
      if (user != null) {
        await CardDatabase.initForUser(user['id'] as int);
      }
    }
    if (mounted) setState(() { _isLoggedIn = loggedIn; _checking = false; });
  }

  void _onLoginSuccess() async {
    final user = await _auth.getCachedUser();
    if (user != null) {
      await CardDatabase.initForUser(user['id'] as int);
      // Sincroniza en background sin bloquear la UI
      SyncService().syncOnLogin();
    }
    if (mounted) setState(() { _isLoggedIn = true; _checking = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: kBlack,
        body: Center(child: CircularProgressIndicator(color: kGold)),
      );
    }
    if (_isLoggedIn) return const AppShell();
    return LoginScreen(onLoginSuccess: _onLoginSuccess);
  }
}