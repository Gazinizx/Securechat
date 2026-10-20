import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:securechat/screens/auth_screen.dart';
import 'package:securechat/screens/home_screen.dart';
import 'package:securechat/services/firebase_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseBootstrap.initialize();
  runApp(const SecureChatApp());
}

class SecureChatApp extends StatelessWidget {
  const SecureChatApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'SecureChat',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF69E6B1),
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF090E19),
          useMaterial3: true,
        ),
        home: Firebase.apps.isEmpty
            ? const FirebaseSetupScreen()
            : const AuthGate(),
      );
}

class FirebaseSetupScreen extends StatelessWidget {
  const FirebaseSetupScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 64, color: Color(0xFF69E6B1)),
                SizedBox(height: 18),
                Text('SecureChat', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                SizedBox(height: 12),
                Text(
                  'Firebase yapılandırması eksik. mobile/README.md içindeki FlutterFire adımlarını tamamlayıp uygulamayı yeniden başlat.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder(
        stream: FirebaseBootstrap.auth.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return snapshot.data == null ? const AuthScreen() : const HomeScreen();
        },
      );
}
