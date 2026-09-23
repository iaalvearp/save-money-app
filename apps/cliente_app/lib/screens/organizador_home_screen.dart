import 'package:flutter/material.dart';

class OrganizadorHomeScreen extends StatelessWidget {
  const OrganizadorHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Organizador')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'Próximamente',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'La gestión de eventos y búsquedas llegará pronto',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}