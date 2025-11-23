import 'package:flutter/material.dart';

void main() {
  runApp(const VoltGuardApp());
}

class VoltGuardApp extends StatelessWidget {
  const VoltGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Volt Guard',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Volt Guard - Energy Management'),
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.energy_savings_leaf,
              size: 100,
              color: Colors.green,
            ),
            SizedBox(height: 20),
            Text(
              'Welcome to Volt Guard',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              'Smart Energy Management System',
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
