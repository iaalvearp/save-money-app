import 'package:flutter/material.dart';

import '../services/notificaciones_service.dart';
import '../widgets/barra_permiso_notificaciones.dart';
import '../widgets/dialogo_error.dart';

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
/// El aviso se guarda en el dispositivo al recibirlo, no al abrir esta pantalla,
/// así que está aquí aunque la app llevara cerrada. Marcar como leída no borra
/// nada: el aviso informaba y sigue informando; borrarlo sería quitarle a
/// alguien la posibilidad de consultarlo.
class BandejaNotificacionesScreen extends StatefulWidget {
  static const titulo = 'Notificaciones';

  /// Inyectan el servicio y la apertura de ajustes en vez de usar los de
  /// verdad. Solo se usan en pruebas.
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
      widget.servicio ?? NotificacionesService.compartido();

  EstadoPermisoNotificaciones? _estado;
  bool _enviandoPrueba = false;

  @override
  void initState() {
    super.initState();
    _servicio.addListener(_alCambiarBuzon);
    // Purga lo que ya caducó y toma lo guardado. Va aquí y no solo al arrancar
    // porque la app puede llevar días sin abrirse.
    _servicio.cargar();
    _evaluarPermiso();
  }

  @override
  void dispose() {
    _servicio.removeListener(_alCambiarBuzon);
    super.dispose();
  }

  void _alCambiarBuzon() {
    if (mounted) setState(() {});
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

  Future<void> _marcarTodasLeidas() async {
    await _servicio.marcarTodasLeidas();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Todo marcado como leído')));
  }

  /// Tocar un aviso lo marca como leído. No lo borra: se puede querer volver a
  /// consultarlo.
  Future<void> _marcarLeida(Notificacion aviso) =>
      _servicio.marcarLeida(aviso.id);

  Future<void> _borrarTodas() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Borrar todas las notificaciones?'),
        content: const Text(
          'Se borrarán de este dispositivo. Es una limpieza local: no deja de '
          'llegar ninguna otra.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;
    await _servicio.borrarTodas();
  }

  Future<void> _enviarPrueba() async {
    setState(() => _enviandoPrueba = true);
    try {
      await _servicio.probarNotificacion();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notificación de prueba enviada. Tarda unos segundos.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      await mostrarErrorDialog(
        context,
        titulo: 'No se pudo enviar',
        mensaje: 'No se pudo enviar la notificación de prueba.',
      );
    } finally {
      if (mounted) setState(() => _enviandoPrueba = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado = _estado;
    final avisos = _servicio.lista;

    return Scaffold(
      appBar: AppBar(
        title: const Text(BandejaNotificacionesScreen.titulo),
        actions: [
          if (avisos.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.done_all),
              tooltip: 'Marcar todas como leídas',
              onPressed: _servicio.noLeidas == 0 ? null : _marcarTodasLeidas,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Borrar todas',
              onPressed: _borrarTodas,
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          if (estado != null)
            BarraPermisoNotificaciones(
              estado: estado,
              onReintentar: _solicitar,
              onAbrirConfiguracion: _abrirConfiguracion,
            ),
          Expanded(
            child: avisos.isEmpty
                ? _vacio(context)
                : ListView.separated(
                    itemCount: avisos.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) => _FilaNotificacion(
                      notificacion: avisos[i],
                      onTocada: () => _marcarLeida(avisos[i]),
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: OutlinedButton.icon(
            onPressed: _enviandoPrueba ? null : _enviarPrueba,
            icon: _enviandoPrueba
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_outlined),
            label: const Text('Enviar una de prueba'),
          ),
        ),
      ),
    );
  }

  Widget _vacio(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_none,
              size: 48,
              color: esquema.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Todavía no hay notificaciones',
              style: TextStyle(color: esquema.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              'Aquí aparecerán los avisos de los eventos a los que te apuntes '
              'y de las promociones Flash que tengas cerca.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: esquema.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Un aviso en la lista. Lo no leído se distingue de un vistazo, sin leer los
/// títulos enteros.
class _FilaNotificacion extends StatelessWidget {
  final Notificacion notificacion;
  final VoidCallback onTocada;

  const _FilaNotificacion({required this.notificacion, required this.onTocada});

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final sinLeer = !notificacion.leida;

    return ListTile(
      onTap: onTocada,
      leading: Icon(
        sinLeer ? Icons.circle : Icons.circle_outlined,
        size: 12,
        color: sinLeer ? esquema.primary : esquema.outlineVariant,
      ),
      title: Text(
        notificacion.titulo,
        style: TextStyle(
          fontWeight: sinLeer ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      subtitle: Text(notificacion.cuerpo, style: const TextStyle(fontSize: 13)),
      trailing: Text(
        _hora(notificacion.fecha),
        style: TextStyle(fontSize: 11, color: esquema.onSurfaceVariant),
      ),
    );
  }

  /// La hora del día, no la fecha completa: la lista está ordenada por fecha y
  /// quien la mira ya sabe que es de hoy o de ayer.
  static String _hora(DateTime fecha) {
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(fecha.hour)}:${dos(fecha.minute)}';
  }
}
