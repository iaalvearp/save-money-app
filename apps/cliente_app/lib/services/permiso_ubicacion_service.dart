import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart'
    show openAppSettings;
import 'package:shared_preferences/shared_preferences.dart';

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

/// Dónde se lleva la cuenta de cuántas veces se ha pedido el permiso.
///
/// Es una sola clave y no una por pantalla porque el permiso de ubicación es
/// del sistema, no de la app: el mismo diálogo aparece en Discover y en Flash,
/// y lo que se niegue en una vale para la otra. Con una clave por pantalla
/// harían falta hasta cuatro rechazos para llegar a los ajustes, y el cuarto
/// diálogo ya no existiría: dos personas distintas verían lo mismo desde sitios
/// distintos.
const _claveIntentos = 'ubicacion_intentos_permisos';

/// Cuántos intentos se hacen antes de dejar de preguntar.
///
/// Android no siempre pasa a `deniedForever` a la segunda negativa: si alguien
/// ticked "no volver a preguntar", más adelante puede seguir devolviendo
/// `denied` para siempre. Tomando la decisión solo de lo que dice el sistema, el
/// botón se quedaba en "Activar ubicación" y al tocarlo no pasaba nada, que es
/// la forma más frustrante de negarle algo a alguien sin decírselo.
const maxIntentosUbicacion = 2;

Future<int> _leerIntentos() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getInt(_claveIntentos) ?? 0;
}

Future<void> _sumarIntento() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_claveIntentos, (prefs.getInt(_claveIntentos) ?? 0) + 1);
}

Future<void> _olvidarIntentos() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_claveIntentos);
}

/// Traduce lo que dice el sistema a lo que la app puede ofrecer.
///
/// Se queda con "ya no se puede preguntar" en cuanto el sistema lo dice o en
/// cuanto se agotan los intentos, lo que pase antes. Cuando se concede, la cuenta
/// se borra: el permiso vuelve a estar disponible y empezar de cero es lo
/// correcto.
Future<ResultadoUbicacion> _clasificar(LocationPermission permiso) async {
  if (permiso == LocationPermission.deniedForever) {
    return ResultadoUbicacion.denegadoPermanente;
  }
  if (permiso == LocationPermission.denied) {
    final intentos = await _leerIntentos();
    return intentos >= maxIntentosUbicacion
        ? ResultadoUbicacion.denegadoPermanente
        : ResultadoUbicacion.denegado;
  }

  await _olvidarIntentos();
  return ResultadoUbicacion.ok;
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
    // Con los intentos agotados no se vuelve a preguntar, aunque el sistema
    // diga que sí se puede. Preguntar igual saca un diálogo que el sistema ya no
    // va a mostrar, y hace creer que la app está colgada.
    if (await _leerIntentos() >= maxIntentosUbicacion) {
      return ResultadoUbicacion.denegadoPermanente;
    }

    // Se cuenta solo cuando se va a mostrar un diálogo de verdad, no cuando se
    // consulta en silencio. Contar las consultas haría agotar los intentos sin
    // que nadie los viera.
    await _sumarIntento();
    permiso = await Geolocator.requestPermission();
  }

  return _clasificar(permiso);
}

/// Abre los ajustes de la app, único camino para revertir un permiso de
/// ubicación denegado permanentemente.
Future<void> abrirConfiguracionUbicacion() => openAppSettings();

/// Abre los ajustes de ubicación del dispositivo, que es donde se enciende el
/// GPS. Es distinto de los ajustes de la app: con el GPS apagado, el permiso
/// puede estar concedido y aun así no haya posición.
Future<void> abrirConfiguracionGps() async {
  await Geolocator.openLocationSettings();
}

/// Consulta el permiso de ubicación sin pedirlo.
///
/// Para el reporte periódico y para volver de segundo plano, que envuelven la
/// app entera: si el usuario no ha concedido el permiso, no se le interrumpe con
/// un diálogo del sistema cada vez que vuelve a primer plano. Si lo concediera
/// antes en Discover, el reporte sigue funcionando.
///
/// Aun así dice `denegadoPermanente` si los intentos ya se agotaron, para que el
/// botón ofrezca los ajustes y no un diálogo que el sistema ya no va a mostrar.
Future<ResultadoUbicacion> comprobarPermisoUbicacion() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    return ResultadoUbicacion.sinPosicion;
  }

  return _clasificar(await Geolocator.checkPermission());
}
