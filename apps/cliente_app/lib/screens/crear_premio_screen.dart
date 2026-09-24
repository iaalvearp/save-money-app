import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/hunt_service.dart';

class CrearPremioScreen extends StatefulWidget {
  final int eventoId;
  final List<Ronda> rondas;
  final HuntService? servicio;
  final AuthService? auth;

  const CrearPremioScreen({
    super.key,
    required this.eventoId,
    this.rondas = const [],
    this.servicio,
    this.auth,
  });

  @override
  State<CrearPremioScreen> createState() => _CrearPremioScreenState();
}

class _CrearPremioScreenState extends State<CrearPremioScreen> {
  late final HuntService _servicio;
  late final AuthService _auth;

  final _nombreController = TextEditingController();
  final _stockController = TextEditingController();
  final _criterioController = TextEditingController();
  String? _tipoSeleccionado;
  int? _rondaSeleccionada;

  bool _enviando = false;
  String? _error;

  final _formKey = GlobalKey<FormState>();

  static const _tipos = [
    'principal',
    'consolacion',
    'frecuencia',
  ];

  @override
  void initState() {
    super.initState();
    _servicio = widget.servicio ?? HuntService();
    _auth = widget.auth ?? AuthService();
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _stockController.dispose();
    _criterioController.dispose();
    super.dispose();
  }

  String? _validarNombre(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'El nombre es requerido';
    }
    return null;
  }

  String? _validarStock(String? value) {
    final stock = int.tryParse(value ?? '');
    if (stock == null || stock <= 0) {
      return 'Stock inválido (debe ser mayor a 0)';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo premio')),
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
              controller: _stockController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Stock',
                border: OutlineInputBorder(),
              ),
              validator: _validarStock,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _tipoSeleccionado,
              decoration: const InputDecoration(
                labelText: 'Tipo',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final tipo in _tipos)
                  DropdownMenuItem(
                    value: tipo,
                    child: Text(_nombreTipo(tipo)),
                  ),
              ],
              onChanged: (value) {
                setState(() => _tipoSeleccionado = value);
              },
              validator: (value) {
                if (value == null) return 'El tipo es requerido';
                return null;
              },
            ),
            if (widget.rondas.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _rondaSeleccionada,
                decoration: const InputDecoration(
                  labelText: 'Ronda (opcional)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final ronda in widget.rondas)
                    DropdownMenuItem(
                      value: ronda.id,
                      child: Text(ronda.nombre ?? 'Ronda ${ronda.id}'),
                    ),
                ],
                onChanged: (value) {
                  setState(() => _rondaSeleccionada = value);
                },
              ),
            ],
            if (_tipoSeleccionado == 'frecuencia') ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _criterioController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Criterio de frecuencia',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
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
              label: const Text('Crear premio'),
            ),
          ],
        ),
      ),
    );
  }

  String _nombreTipo(String tipo) {
    switch (tipo) {
      case 'principal':
        return 'Principal';
      case 'consolacion':
        return 'Consolación';
      case 'frecuencia':
        return 'Frecuencia';
      default:
        return tipo;
    }
  }

  Future<void> _crear() async {
    if (!_formKey.currentState!.validate()) return;

    final criterio = _tipoSeleccionado == 'frecuencia'
        ? int.tryParse(_criterioController.text.trim())
        : null;

    setState(() {
      _enviando = true;
      _error = null;
    });

    try {
      final token = await _auth.getAccessToken();
      await _servicio.crearPremio(
        eventoId: widget.eventoId,
        nombre: _nombreController.text.trim(),
        stock: int.parse(_stockController.text.trim()),
        tipo: _tipoSeleccionado!,
        rondaId: _rondaSeleccionada,
        criterioFrecuencia: criterio,
        token: token,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo crear el premio';
        _enviando = false;
      });
    }
  }
}