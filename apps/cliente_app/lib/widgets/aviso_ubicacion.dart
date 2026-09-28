import 'package:flutter/material.dart';

import '../services/permiso_ubicacion_service.dart';

/// Aviso de que falta la ubicación para poder ordenar lo que hay cerca.
///
/// El botón es único a propósito: cada estado de permiso tiene un solo camino
/// que lo resuelve, así que se ofrece solo ese. Un botón que no funcionaba era
/// justo lo que dejaba al usuario atascado sin saber qué hacer.
class AvisoUbicacion extends StatelessWidget {
  const AvisoUbicacion({
    super.key,
    required this.estado,
    required this.onReintentar,
    this.onAbrirConfiguracion,
    this.onEncenderGps,
    this.mensaje = 'Necesitamos tu ubicación para mostrarte lo que hay cerca',
    this.centrado = true,
  });

  /// Estado del permiso que decide el texto del botón.
  final ResultadoUbicacion estado;

  /// Vuelve a pedir el permiso. Es lo que se ofrece mientras se puede pedir.
  final VoidCallback onReintentar;

  /// Abre los ajustes de la app, para un permiso denegado para siempre.
  final VoidCallback? onAbrirConfiguracion;

  /// Abre los ajustes de ubicación del dispositivo, para el GPS apagado.
  final VoidCallback? onEncenderGps;

  final String mensaje;

  /// Si es `true` ocupa toda la pantalla. Si es `false` se dibuja como una
  /// franja compacta, para poder dejar la lista debajo.
  final bool centrado;

  String get _textoBoton {
    switch (estado) {
      case ResultadoUbicacion.denegadoPermanente:
        return 'Abrir configuración';
      case ResultadoUbicacion.sinPosicion:
        return 'Encender GPS';
      case ResultadoUbicacion.denegado:
      case ResultadoUbicacion.ok:
        return 'Activar ubicación';
    }
  }

  VoidCallback get _accionBoton {
    switch (estado) {
      case ResultadoUbicacion.denegadoPermanente:
        return onAbrirConfiguracion ?? onReintentar;
      case ResultadoUbicacion.sinPosicion:
        return onEncenderGps ?? onReintentar;
      case ResultadoUbicacion.denegado:
      case ResultadoUbicacion.ok:
        return onReintentar;
    }
  }

  IconData get _icono {
    switch (estado) {
      case ResultadoUbicacion.sinPosicion:
        return Icons.gps_off;
      case ResultadoUbicacion.denegado:
      case ResultadoUbicacion.denegadoPermanente:
      case ResultadoUbicacion.ok:
        return Icons.location_off;
    }
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;

    if (!centrado) {
      return Container(
        width: double.infinity,
        color: esquema.surfaceContainerHighest,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Icon(_icono, size: 20, color: esquema.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mensaje,
                    style: TextStyle(
                      fontSize: 13,
                      color: esquema.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: _accionBoton,
                    child: Text(_textoBoton),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icono, size: 48, color: esquema.outline),
            const SizedBox(height: 16),
            Text(
              mensaje,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _accionBoton,
              child: Text(_textoBoton),
            ),
          ],
        ),
      ),
    );
  }
}
