import 'package:flutter/material.dart';

import '../services/notificaciones_service.dart';
import '../widgets/registro_token_notificaciones.dart';
import 'home_screen.dart';
import 'negocio_home_screen.dart';
import 'organizador_home_screen.dart';

const _rolCliente = 'cliente';
const _rolNegocio = 'negocio';
const _rolOrganizador = 'organizador';

/// Pantalla de inicio del rol, envuelta en el registro del token.
///
/// Es el único punto por el que pasan los tres caminos de entrada con sesión
/// (login, registro y sesión guardada), así que el token se registra una vez y
/// sobre la pantalla ya construida, sin bloquear el ingreso. Al entrar ya no se
/// pregunta nada: el permiso se pide desde la campana, donde se explica para qué
/// sirve.
Widget pantallaInicialPorRol(String? rol) {
  // El buzón se comparte y se envuelve acá, que es el punto por el que pasan
  // el login, el registro y la sesión ya guardada: así la campana siempre
  // encuentra el mismo buzón, y el token y los avisos usan el mismo servicio.
  final buzon = NotificacionesService.compartido();
  return NotificacionesScope(
    notifier: buzon,
    child: RegistroTokenNotificaciones(child: _pantallaPorRol(rol)),
  );
}

Widget _pantallaPorRol(String? rol) {
  switch (rol) {
    case _rolNegocio:
      return const NegocioHomeScreen();
    case _rolOrganizador:
      return const OrganizadorHomeScreen();
    case _rolCliente:
    default:
      return const HomeScreen();
  }
}
