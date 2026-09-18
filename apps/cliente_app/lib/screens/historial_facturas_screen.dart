import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/facturas_service.dart';

class HistorialFacturasScreen extends StatefulWidget {
  const HistorialFacturasScreen({super.key});

  @override
  State<HistorialFacturasScreen> createState() =>
      _HistorialFacturasScreenState();
}

class _HistorialFacturasScreenState extends State<HistorialFacturasScreen> {
  final _facturasService = FacturasService();
  final _authService = AuthService();
  List<Factura> _facturas = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarFacturas();
  }

  Future<void> _cargarFacturas() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final token = await _authService.getAccessToken();
      final facturas = await _facturasService.listarMisFacturas(token: token);
      if (!mounted) return;
      setState(() {
        _facturas = facturas;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar las facturas';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis facturas'),
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
                onPressed: _cargarFacturas,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_facturas.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'No tiene facturas registradas',
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargarFacturas,
      child: ListView.builder(
        itemCount: _facturas.length,
        itemBuilder: (context, index) {
          final factura = _facturas[index];
          return _FacturaTile(factura: factura);
        },
      ),
    );
  }
}

class _FacturaTile extends StatelessWidget {
  final Factura factura;

  const _FacturaTile({required this.factura});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _buildIcon(),
      title: _buildTitle(),
      subtitle: _buildSubtitle(),
      trailing: const Icon(Icons.chevron_right),
    );
  }

  Widget _buildIcon() {
    final (icon, color) = switch (factura.estado) {
      'aprobada' => (Icons.check_circle, Colors.green),
      'pendiente_verificacion_sri' => (Icons.hourglass_top, Colors.orange),
      'pendiente_revision_nombre' => (Icons.pending, Colors.orange),
      'rechazada' => (Icons.cancel, Colors.red),
      _ => (Icons.help_outline, Colors.grey),
    };

    return Icon(icon, color: color, size: 32);
  }

  Widget _buildTitle() {
    if (factura.rucEmisor != null && factura.rucEmisor!.isNotEmpty) {
      return Text(
        'RUC: ${factura.rucEmisor}',
        style: const TextStyle(fontWeight: FontWeight.w500),
      );
    }
    return Text(
      'Factura #${factura.id}',
      style: const TextStyle(fontWeight: FontWeight.w500),
    );
  }

  Widget _buildSubtitle() {
    final parts = <String>[];

    parts.add(_estadoLabel());

    if (factura.montoTotal != null) {
      parts.add('\$${factura.montoTotal!.toStringAsFixed(2)}');
    }

    if (factura.fechaFactura != null && factura.fechaFactura!.isNotEmpty) {
      parts.add(factura.fechaFactura!);
    }

    return Text(parts.join(' · '));
  }

  String _estadoLabel() {
    return switch (factura.estado) {
      'aprobada' => 'Aprobada',
      'pendiente_verificacion_sri' => 'Pendiente SRI',
      'pendiente_revision_nombre' => 'Revisión manual',
      'rechazada' => 'Rechazada',
      _ => factura.estado,
    };
  }
}
