import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/comercios_service.dart';
import '../services/hunt_service.dart';

class CuponConsolacionScreen extends StatefulWidget {
  final int eventoId;
  final HuntService? servicio;
  final ComerciosService? comerciosServicio;
  final AuthService? auth;

  const CuponConsolacionScreen({
    super.key,
    required this.eventoId,
    this.servicio,
    this.comerciosServicio,
    this.auth,
  });

  @override
  State<CuponConsolacionScreen> createState() => _CuponConsolacionScreenState();
}

class _CuponConsolacionScreenState extends State<CuponConsolacionScreen> {
  late final HuntService _servicio;
  late final ComerciosService _comerciosServicio;
  late final AuthService _auth;

  List<ParticipanteSinPremio> _participantes = [];
  List<Comercio> _comercios = [];
  final Set<int> _seleccionados = {};
  final _descuentoController = TextEditingController();
  int? _comercioSeleccionado;

  bool _loading = true;
  bool _emitiendo = false;
  String? _error;
  String? _mensaje;

  @override
  void initState() {
    super.initState();
    _servicio = widget.servicio ?? HuntService();
    _comerciosServicio = widget.comerciosServicio ?? ComerciosService();
    _auth = widget.auth ?? AuthService();
    _cargar();
  }

  @override
  void dispose() {
    _descuentoController.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final token = await _auth.getAccessToken();
      final participantes = await _servicio.participantesSinPremio(
        widget.eventoId,
        token: token,
      );
      final comercios = await _comerciosServicio.listar();
      if (!mounted) return;
      setState(() {
        _participantes = participantes;
        _seleccionados.clear();
        _comercios = comercios;
        _comercioSeleccionado = comercios.isEmpty ? null : comercios.first.id;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar los participantes';
        _loading = false;
      });
    }
  }

  Future<void> _emitir() async {
    final comercioId = _comercioSeleccionado;
    if (comercioId == null) {
      setState(() => _error = 'Selecciona un comercio');
      return;
    }
    if (_seleccionados.isEmpty) {
      setState(() => _error = 'Selecciona al menos un participante');
      return;
    }
    final descuento = int.tryParse(_descuentoController.text);
    if (descuento == null || descuento <= 0) {
      setState(() => _error = 'Ingresa un descuento válido');
      return;
    }

    setState(() {
      _emitiendo = true;
      _error = null;
      _mensaje = null;
    });

    try {
      final token = await _auth.getAccessToken();
      await _servicio.emitirCuponesConsolacion(
        eventoId: widget.eventoId,
        comercioId: comercioId,
        usuarioIds: _seleccionados.toList(),
        descuento: descuento,
        token: token,
      );
      if (!mounted) return;
      setState(() {
        _mensaje =
            'Cupones emitidos para ${_seleccionados.length} participante(s)';
        _seleccionados.clear();
        _emitiendo = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron emitir los cupones';
        _emitiendo = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cupón de consolación')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _participantes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _cargar, child: const Text('Reintentar')),
          ],
        ),
      );
    }

    if (_participantes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_outline, size: 48, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Aún no hay participantes sin premio',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8),
              Text(
                'No hay clientes con compras verificadas que todavía '
                'no hayan recibido un premio.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Participantes sin premio (${_participantes.length})',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        if (_comercios.isEmpty)
          Text('No hay comercios disponibles',
              style: TextStyle(color: Colors.grey[500]))
        else
          DropdownButtonFormField<int>(
            initialValue: _comercioSeleccionado,
            decoration: const InputDecoration(
              labelText: 'Comercio',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final c in _comercios)
                DropdownMenuItem(value: c.id, child: Text(c.nombre)),
            ],
            onChanged: (value) {
              setState(() => _comercioSeleccionado = value);
            },
          ),
        const SizedBox(height: 12),
        for (final participante in _participantes)
          CheckboxListTile(
            value: _seleccionados.contains(participante.id),
            onChanged: (value) {
              setState(() {
                if (value == true) {
                  _seleccionados.add(participante.id);
                } else {
                  _seleccionados.remove(participante.id);
                }
              });
            },
            title: Text(participante.nombreCompleto,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(participante.email),
            contentPadding: EdgeInsets.zero,
          ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _descuentoController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Descuento (%)',
            border: OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (_mensaje != null) ...[
          const SizedBox(height: 12),
          Text(_mensaje!, style: const TextStyle(color: Colors.green)),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _emitiendo ? null : _emitir,
          icon: const Icon(Icons.confirmation_num_outlined),
          label: const Text('Emitir cupones'),
        ),
      ],
    );
  }
}