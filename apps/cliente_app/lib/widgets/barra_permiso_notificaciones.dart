import 'package:flutter/material.dart';

import '../services/notificaciones_service.dart';

/// Franja que aparece arriba de la bandeja cuando falta el permiso de
/// notificaciones.
///
/// Hay un solo botón a propósito, igual que en el aviso de ubicación: cada
/// estado de permiso tiene un único camino que lo resuelve, así que se ofrece
/// solo ese. Un botón que no hacía nada era justo lo que dejaba a la persona
/// atascada sin saber qué hacer.
///
/// No se muestra nada con el permiso concedido: la bandeja es lo que importa en
/// ese momento, y una franja que solo dice "ya está bien" estorba.
class BarraPermisoNotificaciones extends StatelessWidget {
  /// Estado actual del permiso.
  final EstadoPermisoNotificaciones estado;

  /// Segundo intento: vuelve a abrir el diálogo del sistema. Se ofrece mientras
  /// el sistema todavía puede mostrarlo.
  final VoidCallback onReintentar;

  /// Abre los ajustes de la app, para un permiso denegado de forma permanente.
  final VoidCallback? onAbrirConfiguracion;

  final String mensaje;

  const BarraPermisoNotificaciones({
    super.key,
    required this.estado,
    required this.onReintentar,
    this.onAbrirConfiguracion,
    this.mensaje = 'Activa las notificaciones para recibir avisos al instante',
  });

  /// Con el permiso concedido la barra no se dibuja: no hay nada que resolver.
  bool get _visible => estado != EstadoPermisoNotificaciones.concedido;

  /// Denegado a perpetuidad: el diálogo del sistema ya no aparecerá, así que
  /// preguntar otra vez sería en vano.
  bool get _esPermanente =>
      estado == EstadoPermisoNotificaciones.denegadoPermanente;

  String get _textoBoton => _esPermanente ? 'Abrir configuración' : 'Activar';

  VoidCallback get _accionBoton =>
      _esPermanente ? (onAbrirConfiguracion ?? onReintentar) : onReintentar;

  IconData get _icono =>
      _esPermanente ? Icons.notifications_off : Icons.notifications_none;

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    final esquema = Theme.of(context).colorScheme;

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
}
