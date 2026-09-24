import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/comercios_service.dart';
import '../services/flash_service.dart';

class CrearPromocionFlashScreen extends StatefulWidget {
  final Comercio comercio;
  final FlashService? servicio;
  final AuthService? auth;

  const CrearPromocionFlashScreen({
    super.key,
    required this.comercio,
    this.servicio,
    this.auth,
  });

  @override
  State<CrearPromocionFlashScreen> createState() =>
      _CrearPromocionFlashScreenState();
}

class _CrearPromocionFlashScreenState
    extends State<CrearPromocionFlashScreen> {
  final _formKey = GlobalKey<FormState>();

  late final FlashService _servicio;
  late final AuthService _auth;

  final _tituloController = TextEditingController();
  final _descuentoController = TextEditingController();
  int _duracionHoras = 24;

  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _servicio = widget.servicio ?? FlashService();
    _auth = widget.auth ?? AuthService();
  }

  @override
  void dispose() {
    _tituloController.dispose();
    _descuentoController.dispose();
    super.dispose();
  }

  String? _validarRequerido(String? value) {
    if (value == null || value.trim().isEmpty) return 'Requerido';
    return null;
  }

  String? _validarDescuento(String? value) {
    if (value == null || value.trim().isEmpty) return 'Requerido';
    final numero = int.tryParse(value.trim());
    if (numero == null) return 'Número inválido';
    if (numero < 1 || numero > 100) return 'Entre 1 y 100';
    return null;
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _guardando = true;
      _error = null;
    });

    try {
      final token = await _auth.getAccessToken();
      final ahora = DateTime.now();
      final termina = ahora.add(Duration(hours: _duracionHoras));

      await _servicio.crearPromocion(
        comercioId: widget.comercio.id,
        titulo: _tituloController.text.trim(),
        descuentoPorcentaje: int.parse(_descuentoController.text.trim())
            .toDouble(),
        iniciaEn: ahora,
        terminaEn: termina,
        categoria: widget.comercio.categoria,
        token: token,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Error de conexión');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva promoción Flash')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Colors.red.shade700),
                  ),
                ),
              Text('Comercio: ${widget.comercio.nombre}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextFormField(
                controller: _tituloController,
                decoration: const InputDecoration(
                  labelText: 'Título',
                  border: OutlineInputBorder(),
                ),
                validator: _validarRequerido,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descuentoController,
                decoration: const InputDecoration(
                  labelText: 'Descuento (%)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: _validarDescuento,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: _duracionHoras,
                decoration: const InputDecoration(
                  labelText: 'Duración',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 hora')),
                  DropdownMenuItem(value: 2, child: Text('2 horas')),
                  DropdownMenuItem(value: 4, child: Text('4 horas')),
                  DropdownMenuItem(value: 6, child: Text('6 horas')),
                  DropdownMenuItem(value: 12, child: Text('12 horas')),
                  DropdownMenuItem(value: 24, child: Text('24 horas')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _duracionHoras = value);
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _guardando ? null : _guardar,
                  child: _guardando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Crear promoción'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}