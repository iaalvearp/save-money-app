import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/hunt_service.dart';
import 'crear_premio_screen.dart';
import 'cupon_consolacion_screen.dart';

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
      appBar: AppBar(
        title: const Text('Premios'),
        actions: [
          IconButton(
            tooltip: 'Cupón de consolación',
            icon: const Icon(Icons.confirmation_num_outlined),
            onPressed: _abrirCuponConsolacion,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _agregarPremio,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo premio'),
      ),
      body: _buildBody(),
    );
  }

  Future<void> _abrirCuponConsolacion() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CuponConsolacionScreen(
          eventoId: widget.eventoId,
          servicio: _servicio,
          auth: _auth,
        ),
      ),
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
            trailing: IconButton(
              tooltip: 'Marcar como entregado',
              icon: const Icon(Icons.how_to_vote),
              onPressed: () => _marcarEntregado(premio),
            ),
          ),
        const SizedBox(height: 16),
        Text(
          'Para marcar un premio como entregado, toca el icono junto a él.',
          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
        ),
      ],
    );
  }

  Future<void> _marcarEntregado(Premio premio) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _GanadoresDialog(
        premio: premio,
        servicio: _servicio,
        auth: _auth,
        onEntregado: _cargar,
      ),
    );
  }
}

class _GanadoresDialog extends StatefulWidget {
  final Premio premio;
  final HuntService servicio;
  final AuthService auth;
  final VoidCallback onEntregado;

  const _GanadoresDialog({
    required this.premio,
    required this.servicio,
    required this.auth,
    required this.onEntregado,
  });

  @override
  State<_GanadoresDialog> createState() => _GanadoresDialogState();
}

class _GanadoresDialogState extends State<_GanadoresDialog> {
  List<GanadorPremio> _ganadores = [];
  bool _loading = true;
  bool _entregando = false;
  String? _error;
  String? _mensaje;

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
      final token = await widget.auth.getAccessToken();
      final ganadores = await widget.servicio.ganadoresDePremio(
        widget.premio.eventoId,
        widget.premio.id,
        token: token,
      );
      if (!mounted) return;
      setState(() {
        _ganadores = ganadores;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar los ganadores';
        _loading = false;
      });
    }
  }

  Future<void> _entregar(GanadorPremio ganador) async {
    setState(() {
      _entregando = true;
      _error = null;
      _mensaje = null;
    });

    try {
      final token = await widget.auth.getAccessToken();
      await widget.servicio.entregarPremio(
        eventoId: widget.premio.eventoId,
        premioId: widget.premio.id,
        usuarioId: ganador.usuarioId,
        rondaId: ganador.rondaId,
        token: token,
      );
      if (!mounted) return;
      widget.onEntregado();
      setState(() {
        _mensaje = 'Premio marcado como entregado';
        _entregando = false;
      });
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().contains('409')
            ? 'Este ganador ya recibió el premio'
            : e.toString().contains('422')
                ? 'El premio ya no tiene stock'
                : 'No se pudo marcar el premio como entregado';
        _entregando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Ganadores de "${widget.premio.nombre}"'),
      content: _buildContent(),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const SizedBox(
        width: 200,
        height: 100,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null && _ganadores.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_error!),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _cargar, child: const Text('Reintentar')),
        ],
      );
    }

    if (_ganadores.isEmpty) {
      return const SizedBox(
        width: 260,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Nadie ha reclamado este premio todavía. '
            'Aún no hay ganadores que marcar como entregado.',
          ),
        ),
      );
    }

    return SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_mensaje != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_mensaje!, style: const TextStyle(color: Colors.green)),
            ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final ganador in _ganadores)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: ganador.estaEntregado
                        ? const Icon(Icons.check_circle,
                            color: Colors.green)
                        : const Icon(Icons.indeterminate_check_box,
                            color: Colors.orange),
                    title: Text(ganador.usuarioNombre ?? 'Usuario',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(ganador.estaEntregado
                        ? 'Entregado'
                        : 'Revocado'),
                    trailing: ganador.estaEntregado
                        ? null
                        : _entregando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : TextButton(
                                onPressed: () => _entregar(ganador),
                                child: const Text('Entregar'),
                              ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}