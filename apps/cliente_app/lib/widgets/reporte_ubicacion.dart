import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/notificaciones_service.dart';
import '../services/permiso_ubicacion_service.dart';

/// Reporta la posición del usuario al backend mientras la app está en primer
/// plano, para activar el disparador de "Flash por cercanía".
///
/// No es un servicio de tracking en background: solo reacciona a que la app
/// vuelva a primer plano y a un intervalo mientras permanece visible.
class ReporteUbicacion extends StatefulWidget {
  final Widget child;
  final NotificacionesService? servicio;
  final Duration intervalo;

  /// Inyecta la comprobación del permiso y la lectura de la posición en vez de
  /// consultar el sistema. Solo se usa en pruebas.
  final Future<ResultadoUbicacion> Function()? comprobarPermiso;
  final Future<Position> Function()? leerPosicion;

  const ReporteUbicacion({
    super.key,
    required this.child,
    this.servicio,
    this.intervalo = const Duration(minutes: 5),
    this.comprobarPermiso,
    this.leerPosicion,
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
      // Se comprueba el permiso antes de tocar el GPS. Si falta, el reporte
      // termina aquí sin lanzar excepción ni interrumpir la app con un
      // diálogo: el permiso se pide desde la pantalla que lo necesita.
      final permiso = await _comprobarPermiso();
      if (permiso != ResultadoUbicacion.ok) return;

      final posicion = await _leerPosicion();
      await _servicio.reportarUbicacion(
        latitude: posicion.latitude,
        longitude: posicion.longitude,
      );
    } catch (_) {
      // Sin señal, sin sesión o sin permiso: el reporte es opcional y
      // no debe interrumpir el uso de la app.
    } finally {
      _reportando = false;
    }
  }

  Future<ResultadoUbicacion> _comprobarPermiso() {
    return widget.comprobarPermiso?.call() ?? comprobarPermisoUbicacion();
  }

  Future<Position> _leerPosicion() {
    return widget.leerPosicion?.call() ??
        Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 8),
          ),
        );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
