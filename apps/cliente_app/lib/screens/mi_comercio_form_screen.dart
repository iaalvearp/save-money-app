import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/comercios_service.dart';

class MiComercioFormScreen extends StatefulWidget {
  final Comercio? comercio;
  final ComerciosService? servicio;
  final AuthService? auth;

  const MiComercioFormScreen({
    super.key,
    this.comercio,
    this.servicio,
    this.auth,
  });

  bool get esEdicion => comercio != null;

  @override
  State<MiComercioFormScreen> createState() => _MiComercioFormScreenState();
}

class _MiComercioFormScreenState extends State<MiComercioFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final ComerciosService _servicio;
  late final AuthService _auth;

  late final _nombreController = TextEditingController(
      text: widget.comercio?.nombre ?? '');
  late final _categoriaController = TextEditingController(
      text: widget.comercio?.categoria ?? '');
  late final _rucController = TextEditingController(
      text: widget.comercio?.ruc ?? '');
  late final _latitudController = TextEditingController(
      text: widget.comercio?.latitud?.toString() ?? '');
  late final _longitudController = TextEditingController(
      text: widget.comercio?.longitud?.toString() ?? '');
  late final _horarioController = TextEditingController(
      text: widget.comercio?.horario ?? '');
  late final _horaAperturaController = TextEditingController(
      text: widget.comercio?.horaApertura ?? '');
  late final _horaCierreController = TextEditingController(
      text: widget.comercio?.horaCierre ?? '');
  late final _fotoUrlController = TextEditingController(
      text: widget.comercio?.fotoUrl ?? '');

  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _servicio = widget.servicio ?? ComerciosService();
    _auth = widget.auth ?? AuthService();
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _categoriaController.dispose();
    _rucController.dispose();
    _latitudController.dispose();
    _longitudController.dispose();
    _horarioController.dispose();
    _horaAperturaController.dispose();
    _horaCierreController.dispose();
    _fotoUrlController.dispose();
    super.dispose();
  }

  String? _validarRequerido(String? value) {
    if (value == null || value.trim().isEmpty) return 'Requerido';
    return null;
  }

  String? _validarHora(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final hora = value.trim();
    if (!RegExp(r'^\d{2}:\d{2}$').hasMatch(hora)) {
      return 'Formato HH:MM';
    }
    final partes = hora.split(':');
    final horas = int.parse(partes[0]);
    final minutos = int.parse(partes[1]);
    if (horas < 0 || horas > 23 || minutos < 0 || minutos > 59) {
      return 'Hora inválida';
    }
    return null;
  }

  double? _parsearNumero(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return double.tryParse(value.trim());
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _guardando = true;
      _error = null;
    });

    final latitud = _parsearNumero(_latitudController.text);
    final longitud = _parsearNumero(_longitudController.text);

    try {
      final token = await _auth.getAccessToken();

      final comercio = widget.comercio;

      if (comercio == null) {
        await _servicio.crear(
          nombre: _nombreController.text.trim(),
          categoria: _normalizarVacio(_categoriaController.text),
          ruc: _normalizarVacio(_rucController.text),
          latitud: latitud,
          longitud: longitud,
          horario: _normalizarVacio(_horarioController.text),
          horaApertura: _normalizarVacio(_horaAperturaController.text),
          horaCierre: _normalizarVacio(_horaCierreController.text),
          fotoUrl: _normalizarVacio(_fotoUrlController.text),
          token: token,
        );
      } else {
        await _servicio.actualizar(
          comercio.id,
          nombre: _nombreController.text.trim(),
          categoria: _normalizarVacio(_categoriaController.text),
          ruc: _normalizarVacio(_rucController.text),
          latitud: latitud,
          longitud: longitud,
          horario: _normalizarVacio(_horarioController.text),
          horaApertura: _normalizarVacio(_horaAperturaController.text),
          horaCierre: _normalizarVacio(_horaCierreController.text),
          fotoUrl: _normalizarVacio(_fotoUrlController.text),
          token: token,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Error de conexión');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  String? _normalizarVacio(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.esEdicion ? 'Editar comercio' : 'Nuevo comercio'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Colors.red.shade700),
                  ),
                ),
              TextFormField(
                controller: _nombreController,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  border: OutlineInputBorder(),
                ),
                validator: _validarRequerido,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _categoriaController,
                decoration: const InputDecoration(
                  labelText: 'Categoría',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _rucController,
                decoration: const InputDecoration(
                  labelText: 'RUC',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _latitudController,
                      decoration: const InputDecoration(
                        labelText: 'Latitud',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^-?\d*\.?\d*')),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _longitudController,
                      decoration: const InputDecoration(
                        labelText: 'Longitud',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^-?\d*\.?\d*')),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _horarioController,
                decoration: const InputDecoration(
                  labelText: 'Horario (ej: Lun a Vie 9:00 - 18:00)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _horaAperturaController,
                      decoration: const InputDecoration(
                        labelText: 'Apertura (HH:MM)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.datetime,
                      validator: _validarHora,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _horaCierreController,
                      decoration: const InputDecoration(
                        labelText: 'Cierre (HH:MM)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.datetime,
                      validator: _validarHora,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _fotoUrlController,
                decoration: const InputDecoration(
                  labelText: 'URL de foto',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _guardando ? null : _guardar,
                  child: _guardando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Guardar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}