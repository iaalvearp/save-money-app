import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/flash_service.dart';

class CanjearCuponScreen extends StatefulWidget {
  final FlashService? servicio;
  final AuthService? auth;

  const CanjearCuponScreen({super.key, this.servicio, this.auth});

  @override
  State<CanjearCuponScreen> createState() => _CanjearCuponScreenState();
}

class _CanjearCuponScreenState extends State<CanjearCuponScreen> {
  late final FlashService _servicio;
  late final AuthService _auth;

  final _codigoController = TextEditingController();

  bool _canjeando = false;
  String? _resultado;
  bool _exitoso = false;

  @override
  void initState() {
    super.initState();
    _servicio = widget.servicio ?? FlashService();
    _auth = widget.auth ?? AuthService();
  }

  @override
  void dispose() {
    _codigoController.dispose();
    super.dispose();
  }

  Future<void> _canjear() async {
    final codigo = _codigoController.text.trim();
    if (codigo.isEmpty) return;

    setState(() {
      _canjeando = true;
      _resultado = null;
    });

    try {
      final token = await _auth.getAccessToken();
      await _servicio.canjearCupon(codigo, token: token);
      if (!mounted) return;
      setState(() {
        _canjeando = false;
        _exitoso = true;
        _resultado = 'Cupón canjeado exitosamente';
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _canjeando = false;
        _exitoso = false;
        _resultado = _mensajeError(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _canjeando = false;
        _exitoso = false;
        _resultado = 'Error de conexión';
      });
    }
  }

  String _mensajeError(ApiException e) {
    final msg = e.message.toLowerCase();
    if (e.statusCode == 404 || msg.contains('no encontrado')) {
      return 'Cupón inválido: verifica el código del cliente';
    }
    if (e.statusCode == 403 || msg.contains('permiso')) {
      return 'Este cupón pertenece a otro comercio';
    }
    if (msg.contains('expirado') || msg.contains('ya fue expirado')) {
      return 'El cupón ya expiró';
    }
    if (msg.contains('utilizado') || msg.contains('ya fue canjeado') ||
        msg.contains('ya fue utilizado')) {
      return 'El cupón ya fue usado';
    }
    return e.message;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Canjear cupón')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Ingresa el código que el cliente te muestra',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _codigoController,
              decoration: const InputDecoration(
                labelText: 'Código del cupón',
                hintText: 'FLASH-XXXXXXXXXXXX',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _canjeando ? null : _canjear,
                child: _canjeando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Canjear'),
              ),
            ),
            if (_resultado != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _exitoso
                      ? Colors.green.shade50
                      : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _exitoso ? Icons.check_circle : Icons.error_outline,
                      color: _exitoso ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _resultado!,
                        style: TextStyle(
                          color: _exitoso
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}