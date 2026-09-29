import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Simula el GPS y el permiso de ubicación como lo haría el teléfono.
///
/// En una prueba de widget no se registra el plugin, así que geolocator usa su
/// implementación de canal genérico y no la de Android. Se simulan los dos
/// canales para que el caso sirva igual si algún día corre en un equipo con el
/// registrant activo.
const canalesGeolocator = [
  MethodChannel('flutter.baseflow.com/geolocator'),
  MethodChannel('flutter.baseflow.com/geolocator_android'),
];

/// Abrir Ajustes lo hace permission_handler, el mismo que usa la cámara.
const canalAjustes = MethodChannel('flutter.baseflow.com/permissions/methods');

/// Valores que el plugin devuelve como enteros.
const denegado = 0;
const denegadoParaSiempre = 1;
const permitido = 2;

/// Instala los mocks. Devuelve el registro para poder inspeccionar lo que se le
/// pidió al sistema.
class LlamadasAlSistema {
  int solicitudes = 0;
  int consultas = 0;
  int lecturasDePosicion = 0;
  int aperturasDeAjustes = 0;
  int aperturasDeGps = 0;

  /// Lo que el sistema contesta a partir de ahora. Se cambia a mitad de un caso
  /// para representar a la persona activando el permiso en los ajustes.
  int permisoActual = denegado;

  /// [permisoTrasSolicitar] permite reproducir la negación de verdad: la primera
  /// vez se rechaza sin querer y la segunda Android ya la da por definitiva.
  /// [siempreDeniega] hace lo contrario, que es lo que pasa cuando alguien
  /// ticked "no volver a preguntar": el sistema no pasa nunca a definitiva, pero
  /// tampoco vuelve a mostrar el diálogo.
  void instalar({
    required bool gpsEncendido,
    required int permiso,
    int? permisoTrasSolicitar,
    bool siempreDeniega = false,
  }) {
    permisoActual = permiso;

    Future<Object?> responder(MethodCall call) async {
      switch (call.method) {
        case 'isLocationServiceEnabled':
          return gpsEncendido;
        case 'checkPermission':
          consultas++;
          return permisoActual;
        case 'requestPermission':
          // Cada llamada es un diálogo nativo nuevo.
          solicitudes++;
          if (siempreDeniega) return denegado;
          return solicitudes == 1
              ? permisoActual
              : (permisoTrasSolicitar ?? permisoActual);
        case 'openAppSettings':
          aperturasDeAjustes++;
          return true;
        case 'openLocationSettings':
          aperturasDeGps++;
          return true;
        case 'getCurrentPosition':
          lecturasDePosicion++;
          return {
            'latitude': -34.6037,
            'longitude': -58.3816,
            'accuracy': 10.0,
            'altitude': 0.0,
            'altitudeAccuracy': 0.0,
            'heading': 0.0,
            'speed': 0.0,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          };
        default:
          return null;
      }
    }

    for (final canal in canalesGeolocator) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(canal, responder);
    }

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(canalAjustes, (call) async {
          if (call.method == 'openAppSettings') {
            aperturasDeAjustes++;
            return true;
          }
          if (call.method == 'openLocationSettings') {
            aperturasDeGps++;
            return true;
          }
          return null;
        });
  }

  void desinstalar() {
    for (final canal in [...canalesGeolocator, canalAjustes]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(canal, null);
    }
  }
}
