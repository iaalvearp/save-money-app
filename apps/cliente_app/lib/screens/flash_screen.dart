import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/flash_service.dart';

class FlashScreen extends StatefulWidget {
  const FlashScreen({super.key});

  @override
  State<FlashScreen> createState() => _FlashScreenState();
}

class _FlashScreenState extends State<FlashScreen> {
  final _flashService = FlashService();
  List<PromocionFlash> _promociones = [];
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
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 5),
          ),
        );
      } catch (_) {}

      if (!mounted) return;

      final promos = await _flashService.listarPromociones(
        lat: pos?.latitude,
        lng: pos?.longitude,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flash'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargar,
          ),
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _cargar,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_promociones.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.flash_off, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'No hay promociones flash activas',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Las promociones aparecerán cuando haya descuentos cerca de ti',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _promociones.length,
        itemBuilder: (context, index) {
          final promo = _promociones[index];
          return _PromocionFlashCard(
            promocion: promo,
            onTap: () => _abrirDetalle(promo),
          );
        },
      ),
    );
  }

  void _abrirDetalle(PromocionFlash promo) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FlashDetalleScreen(promocion: promo),
      ),
    );
  }
}

class _PromocionFlashCard extends StatelessWidget {
  final PromocionFlash promocion;
  final VoidCallback onTap;

  const _PromocionFlashCard({required this.promocion, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.orange.shade700,
                    Colors.orange.shade400,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.flash_on, color: Colors.white, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          promocion.titulo,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (promocion.comercioNombre != null)
                          Text(
                            promocion.comercioNombre!,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '-${promocion.descuentoPorcentaje.toInt()}%',
                      style: TextStyle(
                        color: Colors.orange.shade700,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
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
                  if (promocion.descripcion != null)
                    Text(
                      promocion.descripcion!,
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.access_time,
                          size: 16, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        'Hasta ${promocion.terminaEn.split(' ').first}',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                      const Spacer(),
                      if (promocion.categoria != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            promocion.categoria!,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[700],
                            ),
                          ),
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

class _FlashDetalleScreen extends StatefulWidget {
  final PromocionFlash promocion;

  const _FlashDetalleScreen({required this.promocion});

  @override
  State<_FlashDetalleScreen> createState() => _FlashDetalleScreenState();
}

class _FlashDetalleScreenState extends State<_FlashDetalleScreen> {
  final _flashService = FlashService();
  bool _yaReclamada = false;
  bool _reclamando = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _cargarDetalle();
  }

  Future<void> _cargarDetalle() async {
    try {
      final response =
          await _flashService.obtenerPromocion(widget.promocion.id);
      if (!mounted) return;
      setState(() {
        _yaReclamada = response['ya_reclamada'] as bool? ?? false;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _reclamar() async {
    setState(() => _reclamando = true);

    try {
      final result =
          await _flashService.reclamarPromocion(widget.promocion.id);
      if (!mounted) return;

      final cupon = result['cupon'] as Map<String, dynamic>;
      final mensaje = result['mensaje'] as String;

      setState(() {
        _yaReclamada = true;
        _reclamando = false;
      });

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(Icons.flash_on, color: Colors.orange, size: 48),
          title: const Text('¡Promoción reclamada!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(mensaje, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Tu código:',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      cupon['codigo_qr'] as String,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Muestra este código al cajero para canjear tu descuento',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _reclamando = false);

      String msg = 'Error al reclamar la promoción';
      if (e.toString().contains('409')) {
        msg = 'Ya reclamaste esta promoción';
      } else if (e.toString().contains('422')) {
        msg = 'La promoción ha expirado o no está disponible';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final promo = widget.promocion;

    return Scaffold(
      appBar: AppBar(title: const Text('Promoción Flash')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.orange.shade700,
                          Colors.orange.shade400,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.flash_on,
                            color: Colors.white, size: 64),
                        const SizedBox(height: 16),
                        Text(
                          '-${promo.descuentoPorcentaje.toInt()}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          promo.titulo,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (promo.comercioNombre != null)
                          Text(
                            promo.comercioNombre!,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (promo.descripcion != null) ...[
                          Text(
                            promo.descripcion!,
                            style: const TextStyle(fontSize: 16),
                          ),
                          const SizedBox(height: 16),
                        ],
                        _InfoTile(
                          icon: Icons.access_time,
                          title: 'Válido hasta',
                          subtitle: promo.terminaEn.split(' ').first,
                        ),
                        if (promo.categoria != null)
                          _InfoTile(
                            icon: Icons.category,
                            title: 'Categoría',
                            subtitle: promo.categoria!,
                          ),
                        _InfoTile(
                          icon: Icons.location_on,
                          title: 'Radio',
                          subtitle: '${promo.radioKm} km',
                        ),
                        if (promo.maxUsuarios != null)
                          _InfoTile(
                            icon: Icons.people,
                            title: 'Disponibles',
                            subtitle:
                                '${promo.maxUsuarios! - promo.usuariosNotificados} de ${promo.maxUsuarios}',
                          ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _yaReclamada || _reclamando
                                ? null
                                : _reclamar,
                            icon: _reclamando
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(
                                    _yaReclamada
                                        ? Icons.check_circle
                                        : Icons.flash_on,
                                  ),
                            label: Text(
                              _yaReclamada
                                  ? 'Ya reclamada'
                                  : 'Reclamar descuento',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  _yaReclamada ? Colors.grey : Colors.orange,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
                              textStyle: const TextStyle(fontSize: 16),
                            ),
                          ),
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

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
