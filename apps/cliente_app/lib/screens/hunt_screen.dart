import 'package:flutter/material.dart';

import '../services/hunt_service.dart';

class HuntScreen extends StatefulWidget {
  const HuntScreen({super.key});

  @override
  State<HuntScreen> createState() => _HuntScreenState();
}

class _HuntScreenState extends State<HuntScreen> {
  final _huntService = HuntService();
  List<Evento> _eventos = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final eventos = await _huntService.listarEventos();
      if (!mounted) return;
      setState(() {
        _eventos = eventos;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar los eventos';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hunt'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _cargar),
        ],
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
            Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _cargar, child: const Text('Reintentar')),
          ],
        ),
      );
    }

    if (_eventos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.celebration, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text('No hay eventos disponibles', style: TextStyle(fontSize: 16)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _eventos.length,
        itemBuilder: (context, index) {
          final evento = _eventos[index];
          return _EventoCard(evento: evento);
        },
      ),
    );
  }
}

class _EventoCard extends StatelessWidget {
  final Evento evento;
  const _EventoCard({required this.evento});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _EventoDetalleScreen(eventoId: evento.id),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.deepPurple.shade700, Colors.deepPurple.shade400],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.celebration, color: Colors.white, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          evento.nombre,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (evento.organizadorNombre != null)
                          Text(
                            evento.organizadorNombre!,
                            style: const TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                      ],
                    ),
                  ),
                  if (evento.estaActivo)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Activo',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 16, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        '${evento.fechaInicio.split(' ').first} - ${evento.fechaFin.split(' ').first}',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (evento.requiereEntrada) ...[
                        Icon(Icons.confirmation_number, size: 16, color: Colors.orange[700]),
                        const SizedBox(width: 4),
                        Text(
                          'Entrada: \$${evento.precioEntrada?.toStringAsFixed(2) ?? 'N/A'}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.orange[700],
                          ),
                        ),
                      ] else ...[
                        Icon(Icons.free_cancellation, size: 16, color: Colors.green[700]),
                        const SizedBox(width: 4),
                        Text(
                          'Entrada gratuita',
                          style: TextStyle(fontSize: 13, color: Colors.green[700]),
                        ),
                      ],
                      const Spacer(),
                      if (evento.entradasVendidas != null)
                        Text(
                          '${evento.entradasVendidas} asistentes',
                          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventoDetalleScreen extends StatefulWidget {
  final int eventoId;
  const _EventoDetalleScreen({required this.eventoId});

  @override
  State<_EventoDetalleScreen> createState() => _EventoDetalleScreenState();
}

class _EventoDetalleScreenState extends State<_EventoDetalleScreen> {
  final _huntService = HuntService();
  Evento? _evento;
  List<Ronda> _rondas = [];
  List<Premio> _premios = [];
  List<dynamic> _sponsors = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await _huntService.obtenerEvento(widget.eventoId);
      if (!mounted) return;

      setState(() {
        _evento = Evento.fromJson(response['evento'] as Map<String, dynamic>);
        _rondas = (response['rondas'] as List<dynamic>? ?? [])
            .map((r) => Ronda.fromJson(r as Map<String, dynamic>))
            .toList();
        _premios = (response['premios'] as List<dynamic>? ?? [])
            .map((p) => Premio.fromJson(p as Map<String, dynamic>))
            .toList();
        _sponsors = response['sponsors'] as List<dynamic>? ?? [];
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_evento?.nombre ?? 'Evento')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _cargar, child: const Text('Reintentar')),
                    ],
                  ),
                )
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    final evento = _evento!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(evento),
          const SizedBox(height: 24),
          if (_rondas.isNotEmpty) ...[
            const Text('Rondas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (final r in _rondas)
              ListTile(
                leading: const Icon(Icons.timer),
                title: Text(r.nombre ?? 'Ronda ${r.id}'),
                subtitle: Text('${r.horaInicio} - ${r.horaFin}'),
              ),
            const SizedBox(height: 16),
          ],
          if (_premios.isNotEmpty) ...[
            const Text('Premios', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (final p in _premios)
              ListTile(
                leading: Icon(
                  p.tipo == 'principal' ? Icons.emoji_events : Icons.card_giftcard,
                  color: p.tipo == 'principal' ? Colors.amber : Colors.grey,
                ),
                title: Text(p.nombre),
                subtitle: Text('Stock: ${p.stockDisponible}/${p.stock}'),
                trailing: Text(p.tipo, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ),
            const SizedBox(height: 16),
          ],
          if (_sponsors.isNotEmpty) ...[
            const Text('Patrocinadores', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (final s in _sponsors)
              ListTile(
                leading: Icon(Icons.store, color: Colors.blue[600]),
                title: Text(s['comercio_nombre'] as String? ?? ''),
                subtitle: Text(s['estado'] as String? ?? ''),
              ),
            const SizedBox(height: 16),
          ],
          if (evento.requiereEntrada) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  try {
                    await _huntService.comprarEntrada(evento.id);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Entrada registrada. Sube tu comprobante de pago.')),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(e.toString().contains('409')
                            ? 'Ya tienes una entrada para este evento'
                            : 'Error al comprar entrada'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.confirmation_number),
                label: Text('Comprar entrada - \$${evento.precioEntrada?.toStringAsFixed(2) ?? ''}'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(Evento evento) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.deepPurple.shade700, Colors.deepPurple.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Icon(Icons.celebration, color: Colors.white, size: 48),
          const SizedBox(height: 12),
          Text(
            evento.nombre,
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '${evento.fechaInicio.split(' ').first} - ${evento.fechaFin.split(' ').first}',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          if (evento.requiereEntrada)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Entrada: \$${evento.precioEntrada?.toStringAsFixed(2) ?? 'N/A'}',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ),
        ],
      ),
    );
  }
}
