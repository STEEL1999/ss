import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/browser_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _requestPermissions();
  runApp(const VidBrowserApp());
}

Future<void> _requestPermissions() async {
  // Equivalente a que la app de escritorio ya tenga acceso al filesystem:
  // en Android hay que pedirlo en runtime.
  await [
    Permission.storage,
    Permission.videos,
  ].request();
}

class VidBrowserApp extends StatelessWidget {
  const VidBrowserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VidBrowser',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF27AE60),
        useMaterial3: true,
      ),
      home: const BrowserScreen(),
    );
  }
}
