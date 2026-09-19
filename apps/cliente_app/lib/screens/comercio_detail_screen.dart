import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/comercios_service.dart';
import 'facturacion_screen.dart';

class ComercioDetailScreen extends StatefulWidget {
  final int comercioId;

  const ComercioDetailScreen({super.key, required this.comercioId});

  @override
  State<ComercioDetailScreen> createState() => _ComercioDetailScreenState();
}

class _ComercioDetailScreenState extends State<ComercioDetailScreen> {
  final _comerciosService = ComerciosService();
  Comercio? _comercio;
  List<Promocion> _promociones = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarComercio();
  }

  Future<void> _cargarComercio() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await _comerciosService.obtener(widget.comercioId);
      if (!mounted) return;

      final comercioData = response['comercio'] as Map<String, dynamic>;
      final promocionesData =
          response['promociones'] as List<dynamic>? ?? [];

      setState(() {
        _comercio = Comercio.fromJson(comercioData);
        _promociones = promocionesData
            .map((p) => Promocion.fromJson(p as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el comercio';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_comercio?.nombre ?? 'Comercio'),
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
                onPressed: _cargarComercio,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    final comercio = _comercio!;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFoto(comercio),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(comercio),
                const SizedBox(height: 24),
                if (_promociones.isNotEmpty) ...[
                  _buildPromocionesSection(),
                  const SizedBox(height: 24),
                ],
                _buildInfoSection(comercio),
                const SizedBox(height: 24),
                _buildLocationSection(comercio),
                const SizedBox(height: 32),
                _buildRegistrarButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFoto(Comercio comercio) {
    if (comercio.fotoUrl != null && comercio.fotoUrl!.isNotEmpty) {
      return Image.network(
        comercio.fotoUrl!,
        height: 220,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildFotoPlaceholder(),
      );
    }
    return _buildFotoPlaceholder();
  }

  Widget _buildFotoPlaceholder() {
    return Container(
      height: 220,
      width: double.infinity,
      color: Colors.grey[200],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.store, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 8),
          Text(
            'Sin foto',
            style: TextStyle(color: Colors.grey[500], fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(Comercio comercio) {
    final estaAbierto = _estaAbierto(comercio);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                comercio.nombre,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (comercio.esPatrocinado)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue[700],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Descubierto',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              comercio.categoria ?? 'Sin categoría',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            if (comercio.horaApertura != null && comercio.horaCierre != null) ...[
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: estaAbierto ? Colors.green[50] : Colors.red[50],
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: estaAbierto ? Colors.green[300]! : Colors.red[300]!,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      estaAbierto ? Icons.check_circle : Icons.cancel,
                      size: 14,
                      color: estaAbierto ? Colors.green[700] : Colors.red[700],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      estaAbierto ? 'Abierto' : 'Cerrado',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: estaAbierto ? Colors.green[700] : Colors.red[700],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  bool _estaAbierto(Comercio comercio) {
    if (comercio.horaApertura == null || comercio.horaCierre == null) {
      return false;
    }
    try {
      final ahora = TimeOfDay.now();
      final apertura = _parseTime(comercio.horaApertura!);
      final cierre = _parseTime(comercio.horaCierre!);
      if (apertura == null || cierre == null) return false;

      final ahoraMin = ahora.hour * 60 + ahora.minute;
      final aperturaMin = apertura.hour * 60 + apertura.minute;
      final cierreMin = cierre.hour * 60 + cierre.minute;

      if (aperturaMin <= cierreMin) {
        return ahoraMin >= aperturaMin && ahoraMin < cierreMin;
      } else {
        return ahoraMin >= aperturaMin || ahoraMin < cierreMin;
      }
    } catch (_) {
      return false;
    }
  }

  TimeOfDay? _parseTime(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  Widget _buildPromocionesSection() {
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_offer, size: 20, color: Colors.green[700]),
                const SizedBox(width: 8),
                Text(
                  'Promociones activas',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final promo in _promociones) ...[
              _PromocionTile(promocion: promo),
              if (promo != _promociones.last) const Divider(height: 16),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoSection(Comercio comercio) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Información',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (comercio.horario != null && comercio.horario!.isNotEmpty) ...[
              _InfoRow(
                  icon: Icons.access_time,
                  label: 'Horario',
                  value: comercio.horario!),
              const SizedBox(height: 8),
            ],
            if (comercio.ruc != null && comercio.ruc!.isNotEmpty) ...[
              _InfoRow(
                  icon: Icons.badge, label: 'RUC', value: comercio.ruc!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLocationSection(Comercio comercio) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ubicación',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (comercio.latitud != null && comercio.longitud != null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _abrirGoogleMaps(comercio),
                  icon: const Icon(Icons.directions),
                  label: const Text('Cómo llegar'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              )
            else
              Text(
                'Sin ubicación registrada',
                style: TextStyle(color: Colors.grey[500]),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _abrirGoogleMaps(Comercio comercio) async {
    final lat = comercio.latitud;
    final lng = comercio.longitud;
    if (lat == null || lng == null) return;

    final url = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildRegistrarButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => FacturacionScreen(
                comercioId: widget.comercioId,
                comercioNombre: _comercio?.nombre ?? 'Comercio',
              ),
            ),
          );
        },
        icon: const Icon(Icons.receipt_long),
        label: const Text('Registrar mi compra aquí'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}

class _PromocionTile extends StatelessWidget {
  final Promocion promocion;

  const _PromocionTile({required this.promocion});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.green[700],
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            promocion.descuento != null
                ? '-${promocion.descuento!.toInt()}%'
                : 'Activo',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Código: ${promocion.codigoQr}',
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
              if (promocion.expiraEn != null)
                Text(
                  'Válido hasta: ${promocion.expiraEn!.split('T').first}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
            ],
          ),
        ),
        Icon(Icons.chevron_right, color: Colors.grey[400]),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text('$label: ', style: TextStyle(color: Colors.grey[600])),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
