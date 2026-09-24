import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/hunt_service.dart';

class AgregarRondaScreen extends StatefulWidget {
  final int eventoId;
  final String fechaInicio;
  final String fechaFin;
  final HuntService? servicio;
  final AuthService? auth;

  const AgregarRondaScreen({
    super.key,
    required this.eventoId,
    required this.fechaInicio,
    required this.fechaFin,
    this.servicio,
    this.auth,
  });

  @override
  State<AgregarRondaScreen> createState() => _AgregarRondaScreenState();
}

class _AgregarRondaScreenState extends State<AgregarRondaScreen> {
  late final HuntService _servicio;
  late final AuthService _auth;

  final _nombreController = TextEditingController();
  final _inicioController = TextEditingController();
  final _finController = TextEditingController();

  bool _enviando = false;
  String? _error;

  final _formKey = GlobalKey<FormState>();

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

  String? _validarDentroDelEvento(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'La hora es requerida';
    }
    final dt = DateTime.tryParse(value.trim());
    if (dt == null) {
      return 'Formato inválido (YYYY-MM-DD HH:MM:SS)';
    }
    final inicio = DateTime.tryParse(widget.fechaInicio);
    final fin = DateTime.tryParse(widget.fechaFin);
    if (inicio != null && fin != null) {
      if (!dt.isAfter(inicio)) {
        return 'Debe ser posterior al inicio del evento';
      }
      if (!dt.isBefore(fin)) {
        return 'Debe ser anterior al fin del evento';
      }
    }
    return null;
  }

  String? _validarFinRonda(String? value) {
    final error = _validarDentroDelEvento(value);
    if (error != null) return error;

    final inicio = DateTime.tryParse(_inicioController.text.trim());
    final fin = DateTime.tryParse(value!.trim());
    if (inicio != null && fin != null && !fin.isAfter(inicio)) {
      return 'El fin de la ronda debe ser posterior al inicio';
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
      await _servicio.crearRonda(
        eventoId: widget.eventoId,
        nombre: _nombreController.text.trim(),
        horaInicio: _inicioController.text.trim(),
        horaFin: _finController.text.trim(),
        token: token,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo crear la ronda';
        _enviando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva ronda')),
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
                labelText: 'Hora de inicio',
                hintText: 'YYYY-MM-DD HH:MM:SS',
                border: OutlineInputBorder(),
              ),
              validator: _validarDentroDelEvento,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _finController,
              decoration: const InputDecoration(
                labelText: 'Hora de fin',
                hintText: 'YYYY-MM-DD HH:MM:SS',
                border: OutlineInputBorder(),
              ),
              validator: _validarFinRonda,
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
              label: const Text('Crear ronda'),
            ),
          ],
        ),
      ),
    );
  }
}