import 'package:flutter/material.dart';

import '../widgets/aviso_permiso_notificaciones.dart';
import 'home_screen.dart';
import 'negocio_home_screen.dart';
import 'organizador_home_screen.dart';

const _rolCliente = 'cliente';
const _rolNegocio = 'negocio';
const _rolOrganizador = 'organizador';

/// Pantalla de inicio del rol, envuelta en el aviso de notificaciones.
///
/// Es el único punto por el que pasan los tres caminos de entrada con sesión
/// (login, registro y sesión guardada), así que el aviso se muestra una vez y
/// sobre la pantalla ya construida, sin bloquear el ingreso.
Widget pantallaInicialPorRol(String? rol) {
  return AvisoPermisoNotificaciones(child: _pantallaPorRol(rol));
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