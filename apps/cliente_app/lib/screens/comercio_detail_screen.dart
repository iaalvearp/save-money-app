import 'package:flutter/material.dart';

import '../services/comercios_service.dart';

class ComercioDetailScreen extends StatefulWidget {
  final int comercioId;

  const ComercioDetailScreen({super.key, required this.comercioId});

  @override
  State<ComercioDetailScreen> createState() => _ComercioDetailScreenState();
}

class _ComercioDetailScreenState extends State<ComercioDetailScreen> {
  final _comerciosService = ComerciosService();
  Comercio? _comercio;
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
      final comercio = await _comerciosService.obtener(widget.comercioId);
      if (!mounted) return;
      setState(() {
        _comercio = comercio;
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
                  color: Colors.amber[700],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Patrocinado',
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
        Text(
          comercio.categoria ?? 'Sin categoría',
          style: TextStyle(fontSize: 16, color: Colors.grey[600]),
        ),
      ],
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
              _InfoRow(icon: Icons.access_time, label: 'Horario', value: comercio.horario!),
              const SizedBox(height: 8),
            ],
            if (comercio.ruc != null && comercio.ruc!.isNotEmpty) ...[
              _InfoRow(icon: Icons.badge, label: 'RUC', value: comercio.ruc!),
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
            if (comercio.latitud != null && comercio.longitud != null) ...[
              _InfoRow(
                icon: Icons.location_on,
                label: 'Latitud',
                value: '${comercio.latitud}',
              ),
              const SizedBox(height: 8),
              _InfoRow(
                icon: Icons.location_on,
                label: 'Longitud',
                value: '${comercio.longitud}',
              ),
            ] else
              Text(
                'Sin ubicación registrada',
                style: TextStyle(color: Colors.grey[500]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegistrarButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: null,
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
