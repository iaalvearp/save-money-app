import 'package:flutter/material.dart';

import '../services/notificaciones_service.dart';

/// Registra el token de notificaciones del dispositivo, sin preguntar nada.
///
/// Antes este mismo trabajo lo hacía el aviso que se enseñaba al entrar en la
/// app: un diálogo con "Activar notificaciones", "Ahora no" y "Activar", más
/// un tope de dos apariciones. Ya no hay nada de eso. La campana explica por
/// qué sirven las notificaciones cuando la persona las busca, y ahí se le
/// pregunta.
///
/// Lo que sí hace falta es el registro, y no es un detalle: es lo único que
/// manda el token a `PUT /auth/fcm-token`. Sin él, el backend no sabe a quién
/// avisar y ninguna notificación llega, ni aunque el permiso esté concedido.
///
/// Envuelve la pantalla de inicio ya construida, así que no bloquea el ingreso
/// y el error de registro no interrumpe nada: se traga a propósito, igual que
/// antes, porque no hay nada que el usuario pueda hacer al respecto.
class RegistroTokenNotificaciones extends StatefulWidget {
  final Widget child;
  final NotificacionesService? servicio;

  /// Inyecta el servicio en vez de construirlo. Solo se usa en pruebas.
  const RegistroTokenNotificaciones({
    super.key,
    required this.child,
    this.servicio,
  });

  @override
  State<RegistroTokenNotificaciones> createState() =>
      _RegistroTokenNotificacionesState();
}

class _RegistroTokenNotificacionesState
    extends State<RegistroTokenNotificaciones> {
  late final NotificacionesService _servicio =
      widget.servicio ?? NotificacionesService.compartido();
  bool _registrado = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_registrado) return;
    _registrado = true;
    // Tras el primer frame, para no competir con la construcción de la pantalla.
    WidgetsBinding.instance.addPostFrameCallback((_) => _registrar());
  }

  Future<void> _registrar() async {
    if (!mounted) return;
    await _servicio.registrarToken();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
