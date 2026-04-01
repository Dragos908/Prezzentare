// lib/main.dart (Aplicația Web / Display)

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/firebase_service.dart';
import 'package:go_router/go_router.dart';
import 'features/home/home_page.dart';
import 'features/display/display_page.dart';
import 'features/control/control_gate_page.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;

// Clasa ta cu opțiunile Firebase rămâne neschimbată
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    return web;
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBOW1qjQytXTUKSFnjAnJii35UfhSHP9QM',
    appId: '1:173424712989:web:c072dfe84cdcc3605955f4',
    messagingSenderId: '173424712989',
    projectId: 'proecte-a5f5f',
    authDomain: 'proecte-a5f5f.firebaseapp.com',
    databaseURL: 'https://proecte-a5f5f-default-rtdb.europe-west1.firebasedatabase.app',
    storageBucket: 'proecte-a5f5f.firebasestorage.app',
    measurementId: 'G-ZF926TGEQW',
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Extragem ID-ul proiectului direct din URL-ul browserului
  String proiectTarget = 'proiect1'; // Fallback în caz că nu pui nimic în URL

  if (kIsWeb) {
    final uri = Uri.base;
    if (uri.queryParameters.containsKey('p')) {
      proiectTarget = uri.queryParameters['p']!;
    }
  }

  // Inițializăm Firebase Service specific pentru proiectul detectat
  await FirebaseService.instance.init(proiectTarget);

  runApp(const App());
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path:    '/',
      builder: (_, __) => const HomePage(),
    ),
    GoRoute(
      path:    '/display',
      builder: (_, __) => const DisplayPage(),
    ),
    GoRoute(
      path:    '/control',
      builder: (_, __) => const ControlGatePage(),
    ),
  ],
);

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: _router,
      title:                      'Prezentare Interactivă',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0a0a12),
        colorScheme: const ColorScheme.dark(
          primary:   Color(0xFF6C63FF),
          secondary: Color(0xFF00D9A3),
        ),
      ),
    );
  }
}