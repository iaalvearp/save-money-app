import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

/// Canal de método que usa `permission_handler` para hablar con el sistema.
const canalPermisos = MethodChannel('flutter.baseflow.com/permissions/methods');

const _denegado = 0;
const _concedido = 1;
const _denegadoPermanente = 4;

/// Estado falso de un permiso, con registro de las llamadas hechas al canal.
class FalsoPermisos {
  final List<MethodCall> llamadas = <MethodCall>[];

  int statusActual;
  int statusTrasPedir;

  FalsoPermisos({
    this.statusActual = _denegado,
    this.statusTrasPedir = _concedido,
  });

  /// El usuario ya denegó la cámara permanentemente: pedirla de nuevo no abre
  /// diálogo y Android/iOS devuelven este estado.
  FalsoPermisos.denegadoPermanente()
      : statusActual = _denegado,
        statusTrasPedir = _denegadoPermanente;

  /// `checkPermissionStatus` devuelve [statusActual]; `requestPermissions`
  /// devuelve [statusTrasPedir].
  void instalar() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(canalPermisos, (call) async {
      llamadas.add(call);
      switch (call.method) {
        case 'checkPermissionStatus':
          return statusActual;
        case 'requestPermissions':
          final pedido = (call.arguments as List).cast<int>();
          return <int, int>{
            for (final p in pedido)
              if (p == Permission.camera.value) p: statusTrasPedir
          };
        default:
          return null;
      }
    });
  }

  void desinstalar() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(canalPermisos, null);
  }

  /// Solicitudes de permiso de cámara efectivamente hechas al sistema.
  List<MethodCall> get solicitudesCamara => llamadas
      .where((c) => c.method == 'requestPermissions')
      .where((c) => (c.arguments as List).contains(Permission.camera.value))
      .toList();

  bool get seSolicitoCamara => solicitudesCamara.isNotEmpty;
}
