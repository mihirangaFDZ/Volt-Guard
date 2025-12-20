import 'package:flutter/material.dart';
import 'screens/welcome_screen.dart';

void main() {
  runApp(const VoltGuardApp());
}

class VoltGuardApp extends StatelessWidget {
  const VoltGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Volt Guard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          secondary: Colors.lightGreen,
        ),
        useMaterial3: true,
      ),
      home: const WelcomeScreen(),
    );
  }
}
