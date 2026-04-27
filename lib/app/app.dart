// lib/app/app.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:one_piece_card_scanner/features/collection/presentation/collection_screen.dart';
import 'package:one_piece_card_scanner/features/home/presentation/home_screen.dart';
import 'package:one_piece_card_scanner/features/scanner/presentation/scanner_screen.dart';

class AppEvents {
  static final ValueNotifier<int> collectionVersion = ValueNotifier<int>(0);
  static void notifyCollectionChanged() {
    collectionVersion.value++;
  }

  static final _foldersController = StreamController<void>.broadcast();
  static Stream<void> get onFoldersChanged => _foldersController.stream;
  static void notifyFoldersChanged() {
    _foldersController.add(null);
  }
}

class OnePieceCardScannerApp extends StatelessWidget {
  const OnePieceCardScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'One Piece Card Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        useMaterial3: true,
      ),
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    ScannerScreen(),
    CollectionScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.document_scanner_outlined),
            activeIcon: Icon(Icons.document_scanner),
            label: 'Scanner',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.collections_bookmark_outlined),
            activeIcon: Icon(Icons.collections_bookmark),
            label: 'Collection',
          ),
        ],
      ),
    );
  }
}
