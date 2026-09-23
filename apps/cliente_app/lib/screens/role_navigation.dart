import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'negocio_home_screen.dart';
import 'organizador_home_screen.dart';

const _rolCliente = 'cliente';
const _rolNegocio = 'negocio';
const _rolOrganizador = 'organizador';

Widget pantallaInicialPorRol(String? rol) {
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