import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/facturas_service.dart';
import '../services/ocr_service.dart';

class OcrConfirmResult {
  final int facturaId;
  final String estado;

  const OcrConfirmResult({required this.facturaId, required this.estado});
}

class OcrConfirmScreen extends StatefulWidget {
  final OcrResult ocrResult;
  final int comercioId;
  final String comercioNombre;

  const OcrConfirmScreen({
    super.key,
    required this.ocrResult,
    required this.comercioId,
    required this.comercioNombre,
  });

  @override
  State<OcrConfirmScreen> createState() => _OcrConfirmScreenState();
}

enum _EstadoEnvio { editando, enviando, resultado, error }

class _OcrConfirmScreenState extends State<OcrConfirmScreen> {
  final _facturasService = FacturasService();
  final _authService = AuthService();
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nombreNegocioController;
  late TextEditingController _fechaController;
  late TextEditingController _montoController;
  late TextEditingController _numeroComprobanteController;

  _EstadoEnvio _estado = _EstadoEnvio.editando;
  String? _mensajeError;

  @override
  void initState() {
    super.initState();
    _nombreNegocioController = TextEditingController(
      text: widget.ocrResult.nombreNegocio ?? '',
    );
    _fechaController = TextEditingController(
      text: widget.ocrResult.fecha ?? '',
    );
    _montoController = TextEditingController(
      text: widget.ocrResult.monto != null
          ? widget.ocrResult.monto!.toStringAsFixed(2)
          : '',
    );
    _numeroComprobanteController = TextEditingController(
      text: widget.ocrResult.numeroComprobante ?? '',
    );
  }

  @override
  void dispose() {
    _nombreNegocioController.dispose();
    _fechaController.dispose();
    _montoController.dispose();
    _numeroComprobanteController.dispose();
    super.dispose();
  }

  double? _parseMonto(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^0-9\.\,]'), '').replaceAll(',', '.');
    return double.tryParse(cleaned);
  }

  Future<void> _enviar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _estado = _EstadoEnvio.enviando;
      _mensajeError = null;
    });

    try {
      final token = await _authService.getAccessToken();
      final monto = _parseMonto(_montoController.text);

      final result = await _facturasService.registrarOCR(
        token: token,
        comercioId: widget.comercioId,
        numeroFactura: _numeroComprobanteController.text.isNotEmpty
            ? _numeroComprobanteController.text
            : null,
        nombreCompradorFactura: _nombreNegocioController.text.isNotEmpty
            ? _nombreNegocioController.text
            : null,
        fechaFactura: _fechaController.text.isNotEmpty
            ? _fechaController.text
            : null,
        montoTotal: monto,
      );

      if (!mounted) return;
      setState(() => _estado = _EstadoEnvio.resultado);

      Navigator.of(context).pop(
        OcrConfirmResult(
          facturaId: result.facturaId,
          estado: result.estado,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _estado = _EstadoEnvio.error;
        _mensajeError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _estado = _EstadoEnvio.error;
        _mensajeError = 'Error de conexión. Verifique su internet.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirmar datos'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_estado) {
      case _EstadoEnvio.editando:
        return _buildFormulario();
      case _EstadoEnvio.enviando:
        return _buildEnviando();
      case _EstadoEnvio.resultado:
        return const SizedBox.shrink();
      case _EstadoEnvio.error:
        return _buildError();
    }
  }

  Widget _buildFormulario() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700]),
                const SizedBox(height: 8),
                Expanded(
                  child: Text(
                    'Revise los datos extraídos. Puede corregirlos antes de enviar.',
                    style: TextStyle(fontSize: 14, color: Colors.blue[700]),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildCampoDetectado(
              controller: _nombreNegocioController,
              label: 'Nombre del negocio',
              icono: Icons.store,
              detectado: widget.ocrResult.nombreNegocio != null,
            ),
            const SizedBox(height: 16),
            _buildCampoDetectado(
              controller: _fechaController,
              label: 'Fecha',
              icono: Icons.calendar_today,
              detectado: widget.ocrResult.fecha != null,
              validator: (value) {
                if (value == null || value.isEmpty) return null;
                if (!RegExp(r'^\d{1,2}[/\-]\d{1,2}[/\-]\d{2,4}$').hasMatch(value)) {
                  return 'Formato: DD/MM/YYYY';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            _buildCampoDetectado(
              controller: _montoController,
              label: 'Monto',
              icono: Icons.attach_money,
              detectado: widget.ocrResult.monto != null,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (value) {
                if (value == null || value.isEmpty) return null;
                final cleaned = value.replaceAll(RegExp(r'[^0-9\.\,]'), '');
                if (double.tryParse(cleaned.replaceAll(',', '.')) == null) {
                  return 'Ingrese un monto válido';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            _buildCampoDetectado(
              controller: _numeroComprobanteController,
              label: 'Nº comprobante',
              icono: Icons.confirmation_number,
              detectado: widget.ocrResult.numeroComprobante != null,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _enviar,
              icon: const Icon(Icons.send),
              label: const Text('Confirmar y enviar'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCampoDetectado({
    required TextEditingController controller,
    required String label,
    required IconData icono,
    required bool detectado,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icono),
        border: const OutlineInputBorder(),
        suffixIcon: detectado
            ? Icon(Icons.check_circle, color: Colors.green[600], size: 20)
            : Icon(Icons.edit, color: Colors.grey[400], size: 20),
      ),
    );
  }

  Widget _buildEnviando() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 24),
          Text(
            'Enviando datos...',
            style: TextStyle(fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 72, color: Colors.red[400]),
            const SizedBox(height: 16),
            const Text(
              'Error al enviar',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _mensajeError ?? 'Error desconocido',
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => setState(() => _estado = _EstadoEnvio.editando),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
