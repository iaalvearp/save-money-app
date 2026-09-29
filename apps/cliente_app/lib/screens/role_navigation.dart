import 'package:flutter/material.dart';

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
  return RegistroTokenNotificaciones(child: _pantallaPorRol(rol));
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