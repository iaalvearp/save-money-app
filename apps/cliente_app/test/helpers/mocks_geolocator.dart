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
  int aperturasDeAjustes = 0;
  int aperturasDeGps = 0;

  /// [permisoTrasSolicitar] permite reproducir la negación de verdad: la primera
  /// vez se rechaza sin querer y la segunda Android ya la da por definitiva.
  void instalar({
    required bool gpsEncendido,
    required int permiso,
    int? permisoTrasSolicitar,
  }) {
    Future<Object?> responder(MethodCall call) async {
      switch (call.method) {
        case 'isLocationServiceEnabled':
          return gpsEncendido;
        case 'checkPermission':
          consultas++;
          return permiso;
        case 'requestPermission':
          // Cada llamada es un diálogo nativo nuevo.
          solicitudes++;
          return solicitudes == 1 ? permiso : (permisoTrasSolicitar ?? permiso);
        case 'openAppSettings':
          aperturasDeAjustes++;
          return true;
        case 'openLocationSettings':
          aperturasDeGps++;
          return true;
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
