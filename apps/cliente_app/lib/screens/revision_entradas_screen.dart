import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/hunt_service.dart';

class RevisionEntradasScreen extends StatefulWidget {
  final int eventoId;
  final HuntService? servicio;
  final AuthService? auth;

  const RevisionEntradasScreen({
    super.key,
    required this.eventoId,
    this.servicio,
    this.auth,
  });

  @override
  State<RevisionEntradasScreen> createState() => _RevisionEntradasScreenState();
}

class _RevisionEntradasScreenState extends State<RevisionEntradasScreen> {
  late final HuntService _servicio;
  late final AuthService _auth;

  List<Entrada> _entradas = [];
  bool _loading = true;
  bool _procesando = false;
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
      final entradas = await _servicio.listarEntradas(
        widget.eventoId,
        token: token,
      );
      if (!mounted) return;
      setState(() {
        _entradas = entradas;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar las entradas';
        _loading = false;
      });
    }
  }

  Future<void> _revisar(Entrada entrada, {required bool aprueba}) async {
    setState(() {
      _procesando = true;
      _error = null;
    });

    try {
      final token = await _auth.getAccessToken();
      await _servicio.revisarEntrada(
        entrada.id,
        aprueba: aprueba,
        token: token,
      );
      if (!mounted) return;
      await _cargar();
      if (!mounted) return;
      setState(() => _procesando = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo actualizar la entrada';
        _procesando = false;
      });
    }
  }

  String _estadoTexto(String estado) {
    switch (estado) {
      case 'pendiente_pago':
        return 'Pendiente de pago';
      case 'pendiente_revision_comprobante':
        return 'Pendiente de revisión';
      case 'aprobada':
        return 'Aprobada';
      case 'rechazada':
        return 'Rechazada';
      default:
        return estado;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Revisión de entradas')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _entradas.isEmpty) {
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

    final pendientes = _entradas
        .where((e) => e.estado == 'pendiente_revision_comprobante')
        .toList();

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Entradas pendientes de revisión (${pendientes.length})',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (pendientes.isEmpty)
            Text('Sin entradas pendientes',
                style: TextStyle(color: Colors.grey[500]))
          else
            for (final entrada in pendientes) _buildPendienteCard(entrada),
          const Divider(height: 32),
          const Text(
            'Historial de entradas',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (_entradas.isEmpty)
            Text('Sin entradas registradas',
                style: TextStyle(color: Colors.grey[500]))
          else
            for (final entrada in _entradas)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.confirmation_number),
                title: Text(entrada.clienteNombre ?? 'Cliente'),
                subtitle: Text(_estadoTexto(entrada.estado)),
              ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPendienteCard(Entrada entrada) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entrada.clienteNombre ?? 'Cliente',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (entrada.clienteEmail != null)
              Text(
                entrada.clienteEmail!,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            if (entrada.monto != null)
              Text(
                '\$${entrada.monto!.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            const SizedBox(height: 8),
            _ComprobanteWidget(foto: entrada.comprobanteFoto),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _procesando
                        ? null
                        : () => _revisar(entrada, aprueba: false),
                    icon: const Icon(Icons.close),
                    label: const Text('Rechazar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _procesando
                        ? null
                        : () => _revisar(entrada, aprueba: true),
                    icon: const Icon(Icons.check),
                    label: const Text('Aprobar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ComprobanteWidget extends StatelessWidget {
  final String? foto;

  const _ComprobanteWidget({this.foto});

  @override
  Widget build(BuildContext context) {
    final foto = this.foto;
    if (foto == null || foto.isEmpty) {
      return Container(
        height: 80,
        alignment: Alignment.center,
        color: Colors.grey[200],
        child: Text('Sin comprobante',
            style: TextStyle(color: Colors.grey[600])),
      );
    }

    Widget imagen;
    if (_esBase64(foto)) {
      try {
        final bytes = base64Decode(_limpiarBase64(foto));
        imagen = Image.memory(bytes, height: 120, fit: BoxFit.cover);
      } catch (_) {
        imagen = _fallback(context);
      }
    } else {
      imagen = Image.network(
        foto,
        height: 120,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(context),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: imagen,
    );
  }

  Widget _fallback(BuildContext context) {
    return Container(
      height: 120,
      alignment: Alignment.center,
      color: Colors.grey[200],
      child: Text('No se pudo mostrar el comprobante',
          style: TextStyle(color: Colors.grey[600])),
    );
  }

  bool _esBase64(String foto) {
    return foto.startsWith('data:') || _esCadenaBase64(foto);
  }

  bool _esCadenaBase64(String foto) {
    if (foto.contains(' ')) return false;
    if (foto.startsWith('http')) return false;
    final limpiada = _limpiarBase64(foto);
    return RegExp(
      r'^[A-Za-z0-9+/]+={0,2}$',
    ).hasMatch(limpiada) && limpiada.length > 32;
  }

  String _limpiarBase64(String foto) {
    if (foto.startsWith('data:')) {
      final idx = foto.indexOf(',');
      return idx >= 0 ? foto.substring(idx + 1) : foto;
    }
    return foto;
  }
}