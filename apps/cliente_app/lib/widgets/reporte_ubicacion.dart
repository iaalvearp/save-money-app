import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/notificaciones_service.dart';

/// Reporta la posición del usuario al backend mientras la app está en primer
/// plano, para activar el disparador de "Flash por cercanía".
///
/// No es un servicio de tracking en background: solo reacciona a que la app
/// vuelva a primer plano y a un intervalo mientras permanece visible.
class ReporteUbicacion extends StatefulWidget {
  final Widget child;
  final NotificacionesService? servicio;
  final Duration intervalo;

  const ReporteUbicacion({
    super.key,
    required this.child,
    this.servicio,
    this.intervalo = const Duration(minutes: 5),
  });

  @override
  State<ReporteUbicacion> createState() => _ReporteUbicacionState();
}

class _ReporteUbicacionState extends State<ReporteUbicacion> {
  late final NotificacionesService _servicio;
  Timer? _timer;
  AppLifecycleListener? _listener;
  bool _enPrimerPlano = true;
  bool _reportando = false;

  @override
  void initState() {
    super.initState();
    _servicio = widget.servicio ?? NotificacionesService();

    _listener = AppLifecycleListener(
      onResume: () {
        _enPrimerPlano = true;
        unawaited(_reportar());
      },
      onPause: () => _enPrimerPlano = false,
      onDetach: () => _enPrimerPlano = false,
    );

    _timer = Timer.periodic(widget.intervalo, (_) {
      if (_enPrimerPlano) unawaited(_reportar());
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_reportar()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _listener?.dispose();
    super.dispose();
  }

  Future<void> _reportar() async {
    if (_reportando || !mounted) return;
    _reportando = true;
    try {
      final posicion = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 8),
        ),
      );
      await _servicio.reportarUbicacion(
        latitude: posicion.latitude,
        longitude: posicion.longitude,
      );
    } catch (_) {
      // Sin permiso, sin señal o sin sesión: el reporte es opcional y
      // no debe interrumpir el uso de la app.
    } finally {
      _reportando = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
