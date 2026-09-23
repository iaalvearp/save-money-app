import 'package:flutter/material.dart';

class NegocioHomeScreen extends StatefulWidget {
  const NegocioHomeScreen({super.key});

  @override
  State<NegocioHomeScreen> createState() => _NegocioHomeScreenState();
}

class _NegocioHomeScreenState extends State<NegocioHomeScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mi negocio')),
      body: const Center(
        child: Text('Mis comercios'),
      ),
    );
  }
}