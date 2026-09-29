import 'package:flutter/material.dart';

import '../services/notificaciones_service.dart';
import '../widgets/barra_permiso_notificaciones.dart';

/// Bandeja de notificaciones.
///
/// La campana lleva aquí, y es el sitio donde se pregunta por el permiso.
///
/// El primer intento ocurre al abrir la pantalla, sin aviso previo: la campana
/// ya dice para qué son las notificaciones, y un diálogo de la app encima solo
/// retrasa lo que el sistema va a preguntar igual. Si la persona lo rechaza y lo
/// vuelve a rechazar, el sistema deja de mostrar su diálogo y la barra ofrece ir
/// a los ajustes. El permiso concedido no muestra nada: no hay nada que pedir.
///
/// El token del dispositivo lo registra [RegistroTokenNotificaciones] al entrar
/// en la app, no aquí: esta pantalla solo decide cuándo se pregunta.
class BandejaNotificacionesScreen extends StatefulWidget {
  static const titulo = 'Notificaciones';

  /// Inyectan el servicio y la apertura de ajustes en vez de usar los de verdad.
  /// Solo se usan en pruebas.
  final NotificacionesService? servicio;
  final Future<void> Function()? abrirConfiguracion;

  const BandejaNotificacionesScreen({
    super.key,
    this.servicio,
    this.abrirConfiguracion,
  });

  @override
  State<BandejaNotificacionesScreen> createState() =>
      _BandejaNotificacionesScreenState();
}

class _BandejaNotificacionesScreenState
    extends State<BandejaNotificacionesScreen> {
  late final NotificacionesService _servicio =
      widget.servicio ?? NotificacionesService();

  EstadoPermisoNotificaciones? _estado;

  @override
  void initState() {
    super.initState();
    _evaluarPermiso();
  }

  /// Decide el permiso al abrir la pantalla.
  ///
  /// Si el sistema todavía no ha preguntado nunca, se deja que pregunte: es el
  /// primer intento y no hace falta avisar antes. Si ya se le negó, no se vuelve a
  /// preguntar solo; esa decisión es de la persona y la toma tocando el botón.
  Future<void> _evaluarPermiso() async {
    final estado = await _servicio.estadoPermiso();
    if (!mounted) return;

    if (estado == EstadoPermisoNotificaciones.noDeterminado) {
      await _solicitar();
      return;
    }

    setState(() => _estado = estado);
  }

  Future<void> _solicitar() async {
    final resultado = await _servicio.solicitarPermiso();
    if (!mounted) return;
    setState(() => _estado = resultado);

    // El token solo sirve con el permiso concedido. En Android el sistema ya
    // entrega el token aunque el permiso esté denegado, así que sin esta llamada
    // el backend guardaría un token que no va a recibir nada.
    if (resultado == EstadoPermisoNotificaciones.concedido) {
      await _servicio.registrarToken();
    }
  }

  Future<void> _abrirConfiguracion() async {
    final abrir =
        widget.abrirConfiguracion ?? NotificacionesService.abrirConfiguracion;
    await abrir();
    if (!mounted) return;
    // La persona puede haber activado el permiso desde ahí: se vuelve a leer
    // para que la barra desaparezca sin que tenga que cerrar y abrir la bandeja.
    await _evaluarPermiso();
  }

  @override
  Widget build(BuildContext context) {
    final estado = _estado;

    return Scaffold(
      appBar: AppBar(title: const Text(BandejaNotificacionesScreen.titulo)),
      body: Column(
        children: [
          if (estado != null)
            BarraPermisoNotificaciones(
              estado: estado,
              onReintentar: _solicitar,
              onAbrirConfiguracion: _abrirConfiguracion,
            ),
        ],
      ),
    );
  }
}
