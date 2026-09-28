import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;

/// Resultado de intentar obtener la posición del usuario.
enum ResultadoUbicacion {
  /// Se obtuvo una posición.
  ok,

  /// El permiso está concedido, pero no hay posición disponible todavía o el
  /// servicio está deshabilitado.
  sinPosicion,

  /// El usuario negó el permiso en este momento.
  denegado,

  /// El usuario denegó el permiso para siempre: ya no se puede volver a
  /// preguntar y solo se puede ir a los ajustes.
  denegadoPermanente,
}

/// Comprueba el permiso de ubicación y lo pide solo si aún no se ha
/// consultado.
///
/// Cada consumidor lo llama justo antes de usar la posición, en vez de
/// asumir que otra pantalla ya lo solicitó. Así quien niegue el permiso en
/// Discover no recibe un diálogo inesperado más tarde, y quien lo conceda en
/// Discover no lo vuelve a ver.
Future<ResultadoUbicacion> solicitarPermisoUbicacion() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    return ResultadoUbicacion.sinPosicion;
  }

  var permiso = await Geolocator.checkPermission();

  if (permiso == LocationPermission.denied) {
    permiso = await Geolocator.requestPermission();
  }

  if (permiso == LocationPermission.deniedForever) {
    return ResultadoUbicacion.denegadoPermanente;
  }
  if (permiso == LocationPermission.denied) {
    return ResultadoUbicacion.denegado;
  }

  return ResultadoUbicacion.ok;
}

/// Abre los ajustes de la app, único camino para revertir un permiso de
/// ubicación denegado permanentemente.
Future<void> abrirConfiguracionUbicacion() => openAppSettings();

/// Consulta el permiso de ubicación sin pedirlo.
///
/// Para el reporte periódico, que envuelve la app entera: si el usuario no ha
/// concedido el permiso, no se le interrumpe con un diálogo del sistema cada
/// vez que vuelve a primer plano. Si lo concediera antes en Discover, el
/// reporte sigue funcionando.
Future<ResultadoUbicacion> comprobarPermisoUbicacion() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    return ResultadoUbicacion.sinPosicion;
  }

  final permiso = await Geolocator.checkPermission();

  if (permiso == LocationPermission.deniedForever) {
    return ResultadoUbicacion.denegadoPermanente;
  }
  if (permiso == LocationPermission.denied) {
    return ResultadoUbicacion.denegado;
  }

  return ResultadoUbicacion.ok;
}
