// lib/main.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/firebase_service.dart';
import 'package:go_router/go_router.dart';
import 'features/home/home_page.dart';
import 'features/display/display_page.dart';
import 'features/control/control_gate_page.dart';
import 'features/viewer/viewer_page.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => web;

  static const FirebaseOptions web = FirebaseOptions(
    apiKey:            'AIzaSyBOW1qjQytXTUKSFnjAnJii35UfhSHP9QM',
    appId:             '1:173424712989:web:c072dfe84cdcc3605955f4',
    messagingSenderId: '173424712989',
    projectId:         'proecte-a5f5f',
    authDomain:        'proecte-a5f5f.firebaseapp.com',
    databaseURL:       'https://proecte-a5f5f-default-rtdb.europe-west1.firebasedatabase.app',
    storageBucket:     'proecte-a5f5f.firebasestorage.app',
    measurementId:     'G-ZF926TGEQW',
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Nodul Firebase unde este stocată secvența unică de slide-uri (ID 0–12).
  // Poate fi suprascris din URL cu ?p=alt_nod (util pentru medii de test).
  String projectNode = 'prezentare';

  if (kIsWeb) {
    final uri = Uri.base;
    if (uri.queryParameters.containsKey('p')) {
      projectNode = uri.queryParameters['p']!;
    }
  }

  await FirebaseService.instance.init(projectNode);

  runApp(const App());
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/',        builder: (_, __) => const HomePage()),
    GoRoute(path: '/display', builder: (_, __) => const DisplayPage()),
    GoRoute(path: '/viewer',  builder: (_, __) => const ViewerPage()),
    GoRoute(path: '/control', builder: (_, __) => const ControlGatePage()),
  ],
);

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig:               _router,
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