import 'package:permission_handler/permission_handler.dart';

/// Estados del permiso de cámara, compartidos por todas las pantallas que
/// necesitan la cámara: escaneo QR, comprobante de entrada, captura OCR y
/// captura nivel 3.
enum EstadoPermisoCamara { concediendo, concedido, denegado, denegadoPermanente }

/// Comprueba el permiso de cámara y lo pide solo cuando todavía no se ha
/// consultado. Devuelve el estado resultante para que cada pantalla decida si
/// sigue o muestra el aviso.
Future<EstadoPermisoCamara> solicitarPermisoCamara() async {
  var status = await Permission.camera.status;

  if (status.isDenied) {
    status = await Permission.camera.request();
  }

  if (status.isGranted) return EstadoPermisoCamara.concedido;
  if (status.isPermanentlyDenied) {
    return EstadoPermisoCamara.denegadoPermanente;
  }
  return EstadoPermisoCamara.denegado;
}

/// Abre los ajustes de la app, único camino para revertir un permiso
/// denegado permanentemente.
Future<void> abrirConfiguracion() => openAppSettings();

/// Decide si una captura puede continuar.
///
/// Elegir una foto de la galería no necesita la cámara, así que en ese caso
/// devuelve [EstadoPermisoCamara.concedido] sin tocar el sistema. Solo al
/// photographiar se consulta y pide el permiso.
Future<EstadoPermisoCamara> revisarPermisoParaCaptura({
  required bool requiereCamara,
}) async {
  if (!requiereCamara) return EstadoPermisoCamara.concedido;
  return solicitarPermisoCamara();
}
