import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/comercios_service.dart';
import '../services/flash_service.dart';
import 'crear_promocion_flash_screen.dart';

class MisPromocionesFlashScreen extends StatefulWidget {
  final FlashService? servicio;
  final ComerciosService? comerciosServicio;
  final AuthService? auth;

  const MisPromocionesFlashScreen({
    super.key,
    this.servicio,
    this.comerciosServicio,
    this.auth,
  });

  @override
  State<MisPromocionesFlashScreen> createState() =>
      _MisPromocionesFlashScreenState();
}

class _MisPromocionesFlashScreenState extends State<MisPromocionesFlashScreen> {
  late final FlashService _servicio;
  late final ComerciosService _comerciosServicio;
  late final AuthService _auth;

  List<Comercio> _comercios = [];
  int? _comercioSeleccionado;
  List<PromocionFlash> _promociones = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _servicio = widget.servicio ?? FlashService();
    _comerciosServicio = widget.comerciosServicio ?? ComerciosService();
    _auth = widget.auth ?? AuthService();
    _cargarComercios();
  }

  Future<void> _cargarComercios() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final token = await _auth.getAccessToken();
      final comercios = await _comerciosServicio.misComercios(token: token);
      if (!mounted) return;
      setState(() {
        _comercios = comercios;
        _comercioSeleccionado =
            comercios.isEmpty ? null : comercios.first.id;
      });
      if (comercios.isNotEmpty) {
        await _cargarPromociones();
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar tus comercios';
        _loading = false;
      });
    }
  }

  Future<void> _cargarPromociones() async {
    final comercioId = _comercioSeleccionado;
    if (comercioId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final token = await _auth.getAccessToken();
      final promos = await _servicio.promocionesDeComercio(
        comercioId,
        token: token,
      );
      if (!mounted) return;
      setState(() {
        _promociones = promos;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar las promociones';
        _loading = false;
      });
    }
  }

  Future<void> _crearPromocion() async {
    final comercioId = _comercioSeleccionado;
    if (comercioId == null) return;

    final comercio = _comercios.firstWhere((c) => c.id == comercioId);

    final creada = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CrearPromocionFlashScreen(
          comercio: comercio,
          servicio: _servicio,
          auth: _auth,
        ),
      ),
    );

    if (creada == true) {
      _cargarPromociones();
    }
  }

  String _nombreComercio() {
    for (final c in _comercios) {
      if (c.id == _comercioSeleccionado) return c.nombre;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mis promociones Flash')),
      floatingActionButton: _comercioSeleccionado == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _crearPromocion,
              icon: const Icon(Icons.add),
              label: const Text('Nueva promoción'),
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _cargarComercios,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_comercios.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.store_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'Primero crea un comercio',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Las promociones Flash se crean desde un comercio propio',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargarPromociones,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          if (_comercios.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: DropdownButtonFormField<int>(
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
                  _cargarPromociones();
                },
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                _nombreComercio(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (_promociones.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.local_offer_outlined,
                      size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  const Text(
                    'Sin promociones Flash',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Crea una nueva desde el botón inferior',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            for (final promo in _promociones) _buildPromoTile(promo),
        ],
      ),
    );
  }

  Widget _buildPromoTile(PromocionFlash promo) {
    final activa = promo.estaActiva;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: activa ? Colors.green : Colors.grey,
        child: Text('${promo.descuentoPorcentaje.round()}%'),
      ),
      title: Text(promo.titulo),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${promo.descuentoPorcentaje.toStringAsFixed(0)}% de descuento',
          ),
          const SizedBox(height: 2),
          Text(
            activa ? 'Activa' : promo.estadoTexto,
            style: TextStyle(
              color: activa ? Colors.green : Colors.grey[500],
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}