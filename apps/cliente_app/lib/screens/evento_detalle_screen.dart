import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/hunt_service.dart';
import 'agregar_ronda_screen.dart';

class EventoDetalleScreen extends StatefulWidget {
  final int eventoId;
  final HuntService? servicio;
  final AuthService? auth;

  const EventoDetalleScreen({
    super.key,
    required this.eventoId,
    this.servicio,
    this.auth,
  });

  @override
  State<EventoDetalleScreen> createState() => _EventoDetalleScreenState();
}

class _EventoDetalleScreenState extends State<EventoDetalleScreen> {
  late final HuntService _servicio;
  late final AuthService _auth;

  Evento? _evento;
  List<Ronda> _rondas = [];
  List<Premio> _premios = [];
  List<Sponsor> _sponsors = [];

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
        _evento = Evento.fromJson(response['evento'] as Map<String, dynamic>);
        _rondas = (response['rondas'] as List<dynamic>? ?? [])
            .map((r) => Ronda.fromJson(r as Map<String, dynamic>))
            .toList();
        _premios = (response['premios'] as List<dynamic>? ?? [])
            .map((p) => Premio.fromJson(p as Map<String, dynamic>))
            .toList();
        _sponsors = (response['sponsors'] as List<dynamic>? ?? [])
            .map((s) => Sponsor.fromJson(s as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el evento';
        _loading = false;
      });
    }
  }

  Future<void> _abrirAgregarRonda() async {
    final evento = _evento;
    if (evento == null) return;

    final creada = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AgregarRondaScreen(
          eventoId: evento.id,
          fechaInicio: evento.fechaInicio,
          fechaFin: evento.fechaFin,
          servicio: _servicio,
          auth: _auth,
        ),
      ),
    );

    if (creada == true) {
      _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_evento?.nombre ?? 'Evento')),
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

    final evento = _evento!;
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            evento.nombre,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '${evento.fechaInicio.split(' ').first} - '
            '${evento.fechaFin.split(' ').first}',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          _buildRondasSection(),
          const Divider(height: 24),
          _buildPremiosSection(),
          const Divider(height: 24),
          _buildSponsorsSection(),
        ],
      ),
    );
  }

  Widget _buildRondasSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Rondas',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        if (_rondas.isEmpty)
          Text('Sin rondas todavía', style: TextStyle(color: Colors.grey[500]))
        else
          for (final ronda in _rondas)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.timer),
              title: Text(ronda.nombre ?? 'Ronda ${ronda.id}'),
              subtitle: Text(
                '${_fechaCorta(ronda.horaInicio)} - ${_fechaCorta(ronda.horaFin)}',
              ),
            ),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: _abrirAgregarRonda,
            icon: const Icon(Icons.add),
            label: const Text('Agregar ronda'),
          ),
        ),
      ],
    );
  }

  Widget _buildPremiosSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Premios',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        if (_premios.isEmpty)
          Text('Sin premios todavía', style: TextStyle(color: Colors.grey[500]))
        else
          for (final premio in _premios)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.card_giftcard),
              title: Text(premio.nombre),
              subtitle: Text('Stock: ${premio.stockDisponible}/${premio.stock}'),
            ),
      ],
    );
  }

  Widget _buildSponsorsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Patrocinadores',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
      ],
    );
  }

  String _fechaCorta(String fecha) {
    return fecha.length >= 16 ? fecha.substring(0, 16) : fecha;
  }
}