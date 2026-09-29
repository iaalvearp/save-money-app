import 'package:cliente_app/screens/ocr_capture_screen.dart';
import 'package:cliente_app/screens/ocr_confirm_screen.dart';
import 'package:cliente_app/services/api_client.dart';
import 'package:cliente_app/services/auth_service.dart';
import 'package:cliente_app/services/facturas_service.dart';
import 'package:cliente_app/services/ocr_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'helpers/falso_permisos.dart';

/// Estos tests comprueban que el ticket va por el camino correcto, no que se
/// lean bien los datos: eso esta en ocr_ticket_real_test.dart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ImagePicker pickerFalso;
  late FakeOcrService ocrFalso;
  late FalsoPermisos permisos;
  late FacturasService facturasFalso;
  late AuthService authFalso;

  setUp(() {
    // Devuelve un archivo cualquiera: la foto no se lee, el OCR ya esta
    // inyectado.
    pickerFalso = FakeImagePicker();
    ocrFalso = FakeOcrService()
      ..claveDetectada =
          '2509202601099004196001212120200016735330016735315';
    permisos = FalsoPermisos(statusActual: 1, statusTrasPedir: 1)..instalar();
    facturasFalso = FacturasService(
      api: ApiClient(
        baseUrl: 'http://test',
        httpClient: MockClient((_) async => http.Response(
              '{"factura_id": 77, "estado": "pendiente_revision_nombre"}',
              200,
              headers: {'content-type': 'application/json'},
            )),
      ),
    );
    authFalso = _AuthFalso();
  });

  tearDown(() {
    permisos.desinstalar();
    ocrFalso.dispose();
  });

  /// Monta la pantalla de captura con el OCR inyectado, la abre y devuelve un
  /// completed con lo que la pantalla devuelve al cerrarse. Se usa un
  /// `Completer` porque el `pop` ocurre dentro de un `await` del servicio: leer
  /// una variable en el test puede correr antes de que llegue el valor.
  Future<Completer<OcrTicketResult?>> capturar(WidgetTester tester) async {
    final completer = Completer<OcrTicketResult?>();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                final resultado =
                    await Navigator.of(context).push<OcrTicketResult>(
                  MaterialPageRoute(
                    builder: (_) => OcrCaptureScreen(
                      comercioId: 1,
                      comercioNombre: 'Test Commerce',
                      soportaCamara: true,
                      ocrService: ocrFalso,
                      imagePicker: pickerFalso,
                      facturasService: facturasFalso,
                      authService: authFalso,
                    ),
                  ),
                );
                if (!completer.isCompleted) completer.complete(resultado);
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Elegir de galería'));
    await tester.pumpAndSettle();

    return completer;
  }

  testWidgets('con 49 dígitos devuelve la clave sin pedir revisión manual',
      (WidgetTester tester) async {
    final resultado = await (await capturar(tester)).future;

    // Ni una pantalla de revision: se resuelve en cuanto sale la clave.
    expect(find.byType(OcrConfirmScreen), findsNothing);
    expect(resultado, isA<OcrClaveAccesoLeida>());
    expect(
      (resultado! as OcrClaveAccesoLeida).claveAcceso,
      '2509202601099004196001212120200016735330016735315',
    );
  });

  testWidgets('con 48 dígitos pide la revisión manual',
      (WidgetTester tester) async {
    // El ticket real del usuario: le falta un digito.
    ocrFalso.claveDetectada = null;
    ocrFalso.monto = 11.98;

    final pendiente = await capturar(tester);

    // Se abre la revision manual con el total ya puesto.
    expect(find.byType(OcrConfirmScreen), findsOneWidget);
    expect(find.text('11.98'), findsWidgets);

    // Y si el usuario confirma, vuelve como enviado a mano.
    await tester.tap(find.text('Confirmar y enviar'));
    await tester.pumpAndSettle();

    expect(await pendiente.future, isA<OcrEnviadoAMano>());
  });

  // El OCR ya lee la fecha como viene en el ticket, 2026/09/25. El formulario
  // antes solo aceptaba 25/09/2026 y rechazaba su propia lectura, obligando al
  // usuario a corregir una fecha que estaba bien.
  group('El formulario acepta la fecha tal como la lee el OCR', () {
    Future<void> revisar(WidgetTester tester, String fecha) async {
      ocrFalso.claveDetectada = null;
      await capturar(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Fecha'),
        fecha,
      );
      await tester.tap(find.text('Confirmar y enviar'));
      await tester.pumpAndSettle();
    }

    testWidgets('acepta el formato del ticket, 2026/09/25',
        (WidgetTester tester) async {
      await revisar(tester, '2026/09/25');

      expect(find.text('Fecha no válida'), findsNothing);
    });

    testWidgets('sigue aceptando el formato con el dia primero',
        (WidgetTester tester) async {
      await revisar(tester, '25/09/2026');

      expect(find.text('Fecha no válida'), findsNothing);
    });

    testWidgets('rechaza un dia que no existe', (WidgetTester tester) async {
      await revisar(tester, '31/02/2026');

      expect(find.text('Fecha no válida'), findsOneWidget);
    });

    testWidgets('rechaza un mes que no existe', (WidgetTester tester) async {
      await revisar(tester, '2026/13/25');

      expect(find.text('Fecha no válida'), findsOneWidget);
    });
  });
}

class _AuthFalso extends AuthService {
  @override
  Future<String?> getAccessToken() async => 'token-de-prueba';
}

/// OCR que devuelve siempre el mismo resultado, sin leer ninguna imagen.
class FakeOcrService extends OcrService {
  FakeOcrService({this.claveDetectada});

  /// Lo que el OCR "leyó" de la clave. `null` simula que no se pudo leer.
  String? claveDetectada;
  double? monto;

  @override
  void dispose() {
    // No se llama a super: aqui no hay reconocedor de ML Kit que cerrar y en
    // pruebas ese canal no existe.
  }

  @override
  Future<OcrResult> extraerDatos(String rutaImagen) async {
    return OcrResult(
      nombreNegocio: 'HIPERMARKET VERGELES',
      fecha: '2026/09/25',
      monto: monto,
      numeroComprobante: '121-202-000167353',
      rucEmisor: '0990004196001',
      claveAcceso: claveDetectada,
    );
  }
}

/// Selecciona un archivo sin abrir la galeria del sistema.
class FakeImagePicker extends ImagePicker {
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    return XFile('/tmp/ticket_falso.jpg');
  }
}
