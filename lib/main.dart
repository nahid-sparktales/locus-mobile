import 'dart:async';

import 'package:flutter/material.dart';

import 'src/app_state.dart';
import 'src/screens.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LocusMobileApp());
}

class LocusMobileApp extends StatefulWidget {
  const LocusMobileApp({super.key});

  @override
  State<LocusMobileApp> createState() => _LocusMobileAppState();
}

class _LocusMobileAppState extends State<LocusMobileApp>
    with WidgetsBindingObserver {
  late final LocusAppState state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    state = LocusAppState();
    unawaited(state.initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.resumed &&
        state.isPaired &&
        !state.online) {
      unawaited(state.connect());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Locus Mobile',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF31576D),
          brightness: Brightness.light,
          surface: const Color(0xFFF8F6F0),
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F1E9),
        cardTheme: const CardThemeData(
          color: Color(0xFFFFFDF8),
          elevation: 0,
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFFFFFDF8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFB9F34A),
          brightness: Brightness.dark,
          surface: const Color(0xFF20221C),
        ),
        scaffoldBackgroundColor: const Color(0xFF171914),
        cardTheme: const CardThemeData(
          color: Color(0xFF22251E),
          elevation: 0,
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF252820),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
        ),
      ),
      home: AnimatedBuilder(
        animation: state,
        builder: (context, _) {
          if (!state.initialized) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return state.isPaired
              ? HomeShell(state: state)
              : PairingScreen(state: state);
        },
      ),
    );
  }
}
