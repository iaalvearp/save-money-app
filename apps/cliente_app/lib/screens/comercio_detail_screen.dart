import 'package:flutter/material.dart';

class ComercioDetailScreen extends StatelessWidget {
  final int comercioId;

  const ComercioDetailScreen({super.key, required this.comercioId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Comercio')),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}
