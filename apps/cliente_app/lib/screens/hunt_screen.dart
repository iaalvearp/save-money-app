import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/hunt_service.dart';
import 'comprobante_entrada_screen.dart';

class HuntScreen extends StatefulWidget {
  final HuntService? servicio;
  final AuthService? auth;

  const HuntScreen({super.key, this.servicio, this.auth});

  @override
  State<HuntScreen> createState() => _HuntScreenState();
}

class _HuntScreenState extends State<HuntScreen> {
  late final HuntService _huntService;
  late final AuthService _auth;
  List<Evento> _eventos = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _huntService = widget.servicio ?? HuntService();
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
      final eventos = await _huntService.listarEventos(token: token);
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
          return _EventoCard(
            evento: evento,
            servicio: _huntService,
            auth: _auth,
          );
        },
      ),
    );
  }
}

class _EventoCard extends StatelessWidget {
  final Evento evento;
  final HuntService servicio;
  final AuthService auth;
  const _EventoCard(
      {required this.evento, required this.servicio, required this.auth});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _EventoDetalleScreen(
                eventoId: evento.id,
                servicio: servicio,
                auth: auth,
              ),
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
  final HuntService? servicio;
  final AuthService? auth;
  const _EventoDetalleScreen(
      {required this.eventoId, this.servicio, this.auth});

  @override
  State<_EventoDetalleScreen> createState() => _EventoDetalleScreenState();
}

class _EventoDetalleScreenState extends State<_EventoDetalleScreen> {
  late final HuntService _huntService;
  late final AuthService _auth;
  Evento? _evento;
  List<Ronda> _rondas = [];
  List<Premio> _premios = [];
  List<dynamic> _sponsors = [];

  /// Progreso de los premios por frecuencia, por id de premio.
  ///
  /// Solo entra lo que se pudo traer. Si la consulta falla, el id no aparece
  /// aqui, y el premio se dibuja sin barra y con el boton activo: es peor no
  /// avisar que dejar a alguien esperando, y el backend sigue validando al
  /// reclamar, que es lo unico que decide.
  Map<int, ProgresoFrecuencia> _progresos = {};

  Entrada? _miEntrada;
  bool _comprando = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _huntService = widget.servicio ?? HuntService();
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
      final response = await _huntService.obtenerEvento(widget.eventoId,
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
        _sponsors = response['sponsors'] as List<dynamic>? ?? [];
        _loading = false;
      });

      await _cargarProgresos(token);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el evento';
        _loading = false;
      });
    }
  }

  /// Pregunta el progreso de cada premio por frecuencia.
  ///
  /// Va aparte de la carga del evento porque es informacion extra: si falla, el
  /// evento ya esta en pantalla y se sigue pudiendo usar, solo que sin barra de
  /// progreso. Se consultan todos a la vez y cada uno por separado, porque un
  /// premio sin ventana legible responde 422 y ese error no debe arrastrar a
  /// los demas.
  Future<void> _cargarProgresos(String? token) async {
    final deFrecuencia =
        _premios.where((p) => p.tipo == 'frecuencia').toList();
    if (deFrecuencia.isEmpty) return;

    final pedidos = deFrecuencia.map((premio) async {
      try {
        final progreso = await _huntService.progresoFrecuencia(
          widget.eventoId,
          premio.id,
          token: token,
        );
        return MapEntry(premio.id, progreso);
      } catch (e) {
        // Sin barra y con el boton activo. Se ignora el motivo a proposito: la
        // persona no puede hacer nada con el.
        return MapEntry(premio.id, null);
      }
    });

    final resultados = await Future.wait(pedidos);
    if (!mounted) return;

    setState(() {
      _progresos = {
        for (final r in resultados)
          if (r.value != null) r.key: r.value!,
      };
    });
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
              if (p.tipo == 'frecuencia')
                _buildPremioConFrecuencia(p, evento)
              else
                ListTile(
                  leading: Icon(
                    p.tipo == 'principal'
                        ? Icons.emoji_events
                        : Icons.card_giftcard,
                    color: p.tipo == 'principal' ? Colors.amber : Colors.grey,
                  ),
                  title: Text(p.nombre),
                  subtitle: Text('Stock: ${p.stockDisponible}/${p.stock}'),
                  trailing: _buildReclamar(p, evento),
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
            const Text('Mi entrada',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildMiEntrada(evento),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  /// Un premio por frecuencia, con la barra de progreso.
  ///
  /// Los premios de otros tipos siguen igual. Este lleva su propio diseno
  /// porque necesita mas texto del que cabe en el subtitulo de un ListTile.
  Widget _buildPremioConFrecuencia(Premio premio, Evento evento) {
    final progreso = _progresos[premio.id];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.card_giftcard, color: Colors.grey),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(premio.nombre),
                      const SizedBox(height: 2),
                      Text(
                        'Stock: ${premio.stockDisponible}/${premio.stock}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                _buildReclamar(premio, evento),
              ],
            ),
            if (progreso != null) ...[
              const SizedBox(height: 12),
              Text(
                'Llevas ${progreso.compras} de ${progreso.criterio} compras',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progreso.fraccion,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Cuentan compras de: ${progreso.ventana}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              if (progreso.sinFechaLegible > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '${progreso.sinFechaLegible} factura(s) no se contaron porque '
                  'no se pudo leer su fecha.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReclamar(Premio premio, Evento evento) {
    if (!evento.estaActivo || premio.stockDisponible <= 0) {
      return Text(premio.tipo,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]));
    }

    // El boton se desactiva solo cuando ya sabemos que no cumple. Mientras se
    // carga, o si la carga fallo, se deja activo: el backend vuelve a validar
    // al reclamar, asi que dejarlo activo no regala nada.
    final progreso = _progresos[premio.id];
    final bloqueado = progreso != null && !progreso.cumple;

    return FilledButton.tonal(
      onPressed: bloqueado ? null : () => _reclamarPremio(evento, premio),
      child: const Text('Reclamar'),
    );
  }

  Future<void> _reclamarPremio(Evento evento, Premio premio) async {
    try {
      final token = await _auth.getAccessToken();
      final resultado = await _huntService.reclamarPremio(
        evento.id,
        premio.id,
        token: token,
      );
      if (!mounted) return;
      final mensaje = resultado['mensaje'] as String?;
      final puntos = resultado['puntos_ganados'] as int?;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            puntos != null ? '$mensaje · +$puntos puntos' : mensaje ?? 'Premio reclamado',
          ),
          backgroundColor: Colors.green,
        ),
      );
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().contains('ApiException')
          ? (e as dynamic).message
          : 'Error al reclamar el premio';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildMiEntrada(Evento evento) {
    final entrada = _miEntrada;
    if (entrada != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  entrada.estado == 'aprobada'
                      ? Icons.check_circle
                      : entrada.estado == 'rechazada'
                          ? Icons.cancel
                          : Icons.hourglass_top,
                  color: entrada.estado == 'aprobada'
                      ? Colors.green
                      : entrada.estado == 'rechazada'
                          ? Colors.red
                          : Colors.orange,
                ),
                title: Text(_estadoEntradaLabel(entrada.estado)),
                subtitle: Text('Estado: ${entrada.estado}'),
              ),
              if (entrada.estado == 'pendiente_pago') ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _subirComprobante(entrada),
                    icon: const Icon(Icons.upload),
                    label: const Text('Subir comprobante de pago'),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _comprando ? null : () => _comprarEntrada(evento),
        icon: _comprando
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.confirmation_number),
        label: Text(
            'Comprar entrada - \$${evento.precioEntrada?.toStringAsFixed(2) ?? ''}'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  Future<void> _comprarEntrada(Evento evento) async {
    setState(() => _comprando = true);
    try {
      final token = await _auth.getAccessToken();
      final entrada = await _huntService.comprarEntrada(evento.id, token: token);
      if (!mounted) return;
      setState(() {
        _miEntrada = entrada;
        _comprando = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Entrada registrada. Sube tu comprobante de pago.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _comprando = false);
      final message = e.toString().contains('ApiException')
          ? (e as dynamic).message
          : 'Error al comprar entrada';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _subirComprobante(Entrada entrada) async {
    final subido = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ComprobanteEntradaScreen(
          entradaId: entrada.id,
          servicio: _huntService,
          auth: _auth,
        ),
      ),
    );
    if (subido == true && mounted) {
      setState(() {
        _miEntrada = Entrada(
          id: entrada.id,
          eventoId: entrada.eventoId,
          clienteId: entrada.clienteId,
          estado: 'pendiente_revision_comprobante',
          monto: entrada.monto,
          comprobanteFoto: entrada.comprobanteFoto,
          clienteNombre: entrada.clienteNombre,
          clienteEmail: entrada.clienteEmail,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Comprobante registrado. Revisión: ${_estadoEntradaLabel('pendiente_revision_comprobante')}',
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  String _estadoEntradaLabel(String estado) {
    switch (estado) {
      case 'pendiente_pago':
        return 'Pendiente de pago';
      case 'pendiente_revision_comprobante':
        return 'Comprobante en revisión';
      case 'aprobada':
        return 'Entrada aprobada';
      case 'rechazada':
        return 'Entrada rechazada';
      default:
        return estado;
    }
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
