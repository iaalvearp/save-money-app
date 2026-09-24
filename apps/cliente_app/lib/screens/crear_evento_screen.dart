import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/hunt_service.dart';

class CrearEventoScreen extends StatefulWidget {
  final HuntService? servicio;
  final AuthService? auth;

  const CrearEventoScreen({super.key, this.servicio, this.auth});

  @override
  State<CrearEventoScreen> createState() => _CrearEventoScreenState();
}

class _CrearEventoScreenState extends State<CrearEventoScreen> {
  late final HuntService _servicio;
  late final AuthService _auth;

  final _nombreController = TextEditingController();
  final _inicioController = TextEditingController();
  final _finController = TextEditingController();

  bool _enviando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _servicio = widget.servicio ?? HuntService();
    _auth = widget.auth ?? AuthService();
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _inicioController.dispose();
    _finController.dispose();
    super.dispose();
  }

  String? _validarNombre(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'El nombre es requerido';
    }
    return null;
  }

  String? _validarFecha(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'La fecha es requerida';
    }
    if (DateTime.tryParse(value.trim()) == null) {
      return 'Formato inválido (YYYY-MM-DD HH:MM:SS)';
    }
    return null;
  }

  String? _validarRangoFin(String? value) {
    final error = _validarFecha(value);
    if (error != null) return error;

    final inicio = DateTime.tryParse(_inicioController.text.trim());
    final fin = DateTime.tryParse(value!.trim());
    if (inicio != null && fin != null && !fin.isAfter(inicio)) {
      return 'La fecha de fin debe ser posterior al inicio';
    }
    return null;
  }

  Future<void> _crear() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _enviando = true;
      _error = null;
    });

    try {
      final token = await _auth.getAccessToken();
      await _servicio.crearEvento(
        nombre: _nombreController.text.trim(),
        fechaInicio: _inicioController.text.trim(),
        fechaFin: _finController.text.trim(),
        token: token,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo crear el evento';
        _enviando = false;
      });
    }
  }

  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo evento')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nombreController,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                border: OutlineInputBorder(),
              ),
              validator: _validarNombre,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _inicioController,
              decoration: const InputDecoration(
                labelText: 'Fecha/hora de inicio',
                hintText: 'YYYY-MM-DD HH:MM:SS',
                border: OutlineInputBorder(),
              ),
              validator: _validarFecha,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _finController,
              decoration: const InputDecoration(
                labelText: 'Fecha/hora de fin',
                hintText: 'YYYY-MM-DD HH:MM:SS',
                border: OutlineInputBorder(),
              ),
              validator: _validarRangoFin,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _enviando ? null : _crear,
              icon: const Icon(Icons.add),
              label: const Text('Crear evento'),
            ),
          ],
        ),
      ),
    );
  }
}