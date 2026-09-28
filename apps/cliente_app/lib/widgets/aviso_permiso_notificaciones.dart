import 'package:flutter/material.dart';

import '../services/notificaciones_service.dart';

/// Aviso de una sola vez que explica para qué sirven las notificaciones antes
/// de lanzar el diálogo del sistema.
///
/// Envuelve la pantalla de inicio ya construida, así que no bloquea el ingreso:
/// el usuario puede usarla mientras decide, y si se cierra sin elegir
/// ("Ahora no") no vuelve a aparecer.
class AvisoPermisoNotificaciones extends StatefulWidget {
  static const textoAviso =
      'Te avisamos cuando empiece un Hunt, te aprueben una entrada, ganes un premio o haya una promo cerca.';

  final Widget child;
  final NotificacionesService? servicio;

  /// Inyecta el servicio en vez de construirlo. Solo se usa en pruebas.
  const AvisoPermisoNotificaciones({
    super.key,
    required this.child,
    this.servicio,
  });

  @override
  State<AvisoPermisoNotificaciones> createState() =>
      _AvisoPermisoNotificacionesState();
}

class _AvisoPermisoNotificacionesState extends State<AvisoPermisoNotificaciones> {
  late final NotificacionesService _servicio = widget.servicio ?? NotificacionesService();
  bool _evaluado = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_evaluado) return;
    _evaluado = true;
    // Tras el primer frame, para que el diálogo aparezca sobre la pantalla ya
    // pintada y no sustituya su contenido.
    WidgetsBinding.instance.addPostFrameCallback((_) => _evaluar());
  }

  Future<void> _evaluar() async {
    if (!mounted) return;
    if (await _servicio.debeMostrarAviso()) {
      await _preguntar();
    }
    // El token se registra siempre, como antes, pero después de la decisión:
    // así el backend ya sabe a quién avisar si el usuario activó las
    // notificaciones, y si dijo "Ahora no" el registro sigue siendo válido
    // para cuando active el permiso por su cuenta.
    if (mounted) await _servicio.registrarToken();
  }

  Future<void> _preguntar() async {
    final activar = await showDialog<bool>(
      context: context,
      // Sin "cerrar tocando fuera": siempre tiene que haber una decisión, o el
      // aviso volvería a saltar en el próximo arranque.
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Activar notificaciones'),
        content: const Text(AvisoPermisoNotificaciones.textoAviso),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Ahora no'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Activar'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    // Se recuerda la respuesta tanto si aceptó como si no: el sistema ya
    // guardó su decisión, y repetir el aviso no aporta nada.
    await _servicio.registrarDecisionAviso();

    if (activar == true) {
      await _servicio.solicitarPermiso();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
