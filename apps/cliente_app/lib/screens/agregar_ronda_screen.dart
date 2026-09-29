import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/hunt_service.dart';
import '../widgets/selector_fecha_hora.dart';

class AgregarRondaScreen extends StatefulWidget {
  final int eventoId;
  final String fechaInicio;
  final String fechaFin;
  final HuntService? servicio;
  final AuthService? auth;

  /// Sustituyen al calendario y al reloj del sistema en pruebas.
  final PedirFecha? pedirFecha;
  final PedirHora? pedirHora;

  const AgregarRondaScreen({
    super.key,
    required this.eventoId,
    required this.fechaInicio,
    required this.fechaFin,
    this.servicio,
    this.auth,
    this.pedirFecha,
    this.pedirHora,
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

  /// Inicio de la ronda, para que el selector de fin no pase de ahí.
  DateTime? _inicioRonda;

  bool _enviando = false;
  String? _error;

  final _formKey = GlobalKey<FormState>();

  /// Ventana del evento: una ronda no puede empezar antes de que empiece el
  /// evento ni terminar después de que termine.
  DateTime get _inicioEvento =>
      DateTime.tryParse(widget.fechaInicio) ?? DateTime(2000, 1, 1);
  DateTime get _finEvento =>
      DateTime.tryParse(widget.fechaFin) ?? DateTime(2100, 1, 1);

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
      // Los dos extremos cuentan: el selector deja elegir justo la hora de
      // inicio y la de fin del evento, asi que aqui tambien se aceptan.
      if (dt.isBefore(inicio)) {
        return 'Debe ser posterior al inicio del evento';
      }
      if (dt.isAfter(fin)) {
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
            SelectorFechaHora(
              controller: _inicioController,
              label: 'Hora de inicio',
              minimo: _inicioEvento,
              maximo: _finEvento,
              validator: _validarDentroDelEvento,
              pedirFecha: widget.pedirFecha,
              pedirHora: widget.pedirHora,
              onCambiado: (valor) => setState(() {
                _inicioRonda = valor;
                if (valor != null && SelectorFechaHora.leer(_finController.text) != null) {
                  _formKey.currentState?.validate();
                }
              }),
            ),
            const SizedBox(height: 12),
            SelectorFechaHora(
              controller: _finController,
              label: 'Hora de fin',
              minimo: _inicioRonda ?? _inicioEvento,
              maximo: _finEvento,
              validator: _validarFinRonda,
              pedirFecha: widget.pedirFecha,
              pedirHora: widget.pedirHora,
              onCambiado: (_) => _formKey.currentState?.validate(),
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