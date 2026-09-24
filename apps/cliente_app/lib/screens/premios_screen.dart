import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/hunt_service.dart';
import 'crear_premio_screen.dart';

class PremiosScreen extends StatefulWidget {
  final int eventoId;
  final HuntService? servicio;
  final AuthService? auth;

  const PremiosScreen({
    super.key,
    required this.eventoId,
    this.servicio,
    this.auth,
  });

  @override
  State<PremiosScreen> createState() => _PremiosScreenState();
}

class _PremiosScreenState extends State<PremiosScreen> {
  late final HuntService _servicio;
  late final AuthService _auth;

  List<Premio> _premios = [];
  List<Ronda> _rondas = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _servicio = widget.servicio ?? HuntService();
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
      if (!mounted) return;
      setState(() {
        _premios = (response['premios'] as List<dynamic>? ?? [])
            .map((p) => Premio.fromJson(p as Map<String, dynamic>))
            .toList();
        _rondas = (response['rondas'] as List<dynamic>? ?? [])
            .map((r) => Ronda.fromJson(r as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar los premios';
        _loading = false;
      });
    }
  }

  Future<void> _agregarPremio() async {
    final creado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CrearPremioScreen(
          eventoId: widget.eventoId,
          rondas: _rondas,
          servicio: _servicio,
          auth: _auth,
        ),
      ),
    );

    if (creado == true) {
      _cargar();
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Premios')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _agregarPremio,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo premio'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
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

    if (_premios.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.card_giftcard, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'Sin premios',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Agrega un premio desde el botón inferior',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final premio in _premios)
          ListTile(
            leading: Icon(
              premio.tipo == 'principal'
                  ? Icons.emoji_events
                  : Icons.card_giftcard,
              color: premio.tipo == 'principal' ? Colors.amber : Colors.grey,
            ),
            title: Text(premio.nombre),
            subtitle: Text(
              '${_nombreTipo(premio.tipo)} · '
              'Stock: ${premio.stockDisponible}/${premio.stock}',
            ),
          ),
      ],
    );
  }
}