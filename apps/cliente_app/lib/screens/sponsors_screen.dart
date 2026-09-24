import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/comercios_service.dart';
import '../services/hunt_service.dart';

class SponsorsScreen extends StatefulWidget {
  final int eventoId;
  final HuntService? servicio;
  final ComerciosService? comerciosServicio;
  final AuthService? auth;

  const SponsorsScreen({
    super.key,
    required this.eventoId,
    this.servicio,
    this.comerciosServicio,
    this.auth,
  });

  @override
  State<SponsorsScreen> createState() => _SponsorsScreenState();
}

class _SponsorsScreenState extends State<SponsorsScreen> {
  late final HuntService _servicio;
  late final ComerciosService _comerciosServicio;
  late final AuthService _auth;

  List<Sponsor> _sponsors = [];
  List<Comercio> _comercios = [];
  int? _comercioSeleccionado;

  bool _loading = true;
  bool _invitando = false;
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

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final token = await _auth.getAccessToken();
      final response = await _servicio.obtenerEvento(widget.eventoId,
          token: token);
      final comercios = await _comerciosServicio.listar();
      if (!mounted) return;
      setState(() {
        _sponsors = (response['sponsors'] as List<dynamic>? ?? [])
            .map((s) => Sponsor.fromJson(s as Map<String, dynamic>))
            .toList();
        _comercios = comercios;
        _comercioSeleccionado =
            comercios.isEmpty ? null : comercios.first.id;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar los sponsors';
        _loading = false;
      });
    }
  }

  Future<void> _invitar() async {
    final comercioId = _comercioSeleccionado;
    if (comercioId == null) return;

    setState(() {
      _invitando = true;
      _error = null;
      _mensaje = null;
    });

    try {
      final token = await _auth.getAccessToken();
      await _servicio.invitarSponsor(
        eventoId: widget.eventoId,
        comercioId: comercioId,
        token: token,
      );
      if (!mounted) return;
      await _cargar();
      if (!mounted) return;
      setState(() {
        _mensaje = 'Invitación enviada';
        _invitando = false;
      });
    } catch (e) {
      if (!mounted) return;
      final mensaje = e.toString().contains('409')
          ? 'Ya existe una invitación para ese comercio'
          : 'No se pudo enviar la invitación';
      setState(() {
        _error = mensaje;
        _invitando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sponsors')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _sponsors.isEmpty) {
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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Invitaciones enviadas',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        if (_sponsors.isEmpty)
          Text('Sin invitaciones todavía',
              style: TextStyle(color: Colors.grey[500]))
        else
          for (final sponsor in _sponsors)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.store),
              title: Text(sponsor.comercioNombre ?? ''),
              subtitle: Text(sponsor.estado),
            ),
        const Divider(height: 24),
        const Text(
          'Invitar a un comercio',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (_comercios.isEmpty)
          Text('No hay comercios disponibles',
              style: TextStyle(color: Colors.grey[500]))
        else ...[
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
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_mensaje != null)
            Text(
              _mensaje!,
              style: const TextStyle(color: Colors.green),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _invitando ? null : _invitar,
            icon: const Icon(Icons.send),
            label: const Text('Invitar'),
          ),
        ],
      ],
    );
  }
}