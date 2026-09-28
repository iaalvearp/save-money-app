import 'package:cliente_app/screens/ajustes_sheet.dart';
import 'package:cliente_app/screens/home_screen.dart';
import 'package:cliente_app/screens/factura_detalle_screen.dart';
import 'package:cliente_app/screens/historial_facturas_screen.dart';
import 'package:cliente_app/services/auth_service.dart';
import 'package:cliente_app/services/comercios_service.dart';
import 'package:cliente_app/services/facturas_service.dart';
import 'package:cliente_app/services/permiso_ubicacion_service.dart';
import 'package:cliente_app/services/theme_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// El detalle de una factura es de solo lectura: hay que ver por que se
/// rechazo, no poder arreglarlo a mano desde el movil.
Factura _factura({
  String estado = 'aprobada',
  String? motivo,
  int? nivel = 1,
}) {
  return Factura(
    id: 42,
    estado: estado,
    numeroFactura: '001-001-00000042',
    rucEmisor: '1790012345001',
    fechaFactura: '2026-03-15',
    montoTotal: 12.5,
    descuentoAplicado: 2.5,
    nivelVerificacion: nivel,
    motivoRechazo: motivo,
  );
}

void main() {
  group('Detalle de factura', () {
    testWidgets('una factura aprobada enseña sus datos y está en revisión si toca',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FacturaDetalleSheet(factura: _factura()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Aprobada'), findsOneWidget);
      expect(find.text('1790012345001'), findsOneWidget);
      expect(find.text('001-001-00000042'), findsOneWidget);
      expect(find.text('2026-03-15'), findsOneWidget);
      expect(find.text(r'$12.50'), findsOneWidget);
      expect(find.text('Nivel 1 · Clave de acceso'), findsOneWidget);
      expect(find.textContaining('solo lectura'), findsOneWidget);

      // Nada editable: ni campos de texto, ni guardar, ni enviar.
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(EditableText), findsNothing);
      expect(find.text('Guardar'), findsNothing);
      expect(find.text('Reenviar'), findsNothing);
    });

    testWidgets('una factura rechazada enseña el motivo', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FacturaDetalleSheet(
              factura: Factura(
                id: 7,
                estado: 'rechazada',
                numeroFactura: '001-001-00000007',
                rucEmisor: '0991234567001',
                montoTotal: 8,
                nivelVerificacion: 2,
                motivoRechazo:
                    'La clave de acceso no existe en los registros del SRI',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rechazada'), findsOneWidget);
      expect(find.text('Motivo'), findsOneWidget);
      expect(
        find.text('La clave de acceso no existe en los registros del SRI'),
        findsOneWidget,
      );
      expect(find.text('Nivel 2 · Comprobante'), findsOneWidget);
      expect(find.text('001-001-00000007'), findsOneWidget);
    });

    testWidgets('una factura sin motivo de rechazo no inventa uno',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FacturaDetalleSheet(
              factura: Factura(id: 9, estado: 'rechazada', montoTotal: 3),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rechazada'), findsOneWidget);
      expect(find.text('Motivo'), findsNothing);
      expect(find.text('Sin número'), findsOneWidget);
      expect(find.text('Sin fecha'), findsOneWidget);
    });

    test('los estados internos del servidor se leen como en revisión', () {
      const pendientes = [
        'pendiente_verificacion_sri',
        'pendiente_revision_nombre',
        'pendiente_revision_comprobante',
        'pendiente_pago',
      ];

      for (final estado in pendientes) {
        expect(
          FacturaDetalleSheet.estadoSimple(estado),
          'En revisión',
          reason: '$estado debería leerse como En revisión',
        );
      }

      expect(FacturaDetalleSheet.estadoSimple('aprobada'), 'Aprobada');
      expect(FacturaDetalleSheet.estadoSimple('rechazada'), 'Rechazada');
    });

    testWidgets('tocar una factura de la lista abre su detalle',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HistorialFacturasScreen(
            servicio: _FacturasFalsas(),
            auth: _AuthFalso(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('RUC: 1790012345001'));
      await tester.pumpAndSettle();

      expect(find.byType(FacturaDetalleSheet), findsOneWidget);
      expect(find.text('Aprobada'), findsOneWidget);

      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
      expect(find.byType(FacturaDetalleSheet), findsNothing);
    });
  });

  group('Mis facturas sale del inicio', () {
    testWidgets('la barra del inicio ya no tiene el botón de facturas',
        (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            servicio: _ComerciosVacios(),
            permisoUbicacion: () async => ResultadoUbicacion.denegado,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Mis facturas'), findsNothing);
      expect(find.byIcon(Icons.receipt_long), findsNothing);

      // Los demás accesos del inicio siguen en su sitio.
      expect(find.byTooltip('Flash'), findsOneWidget);
      expect(find.byTooltip('Hunt'), findsOneWidget);
      expect(find.byTooltip('Ajustes'), findsOneWidget);
    });
  });

  group('Mis facturas vive en Ajustes', () {
    testWidgets('la hoja de ajustes ofrece entrar a las facturas',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final themeService = await ThemeService.cargar();

      await tester.pumpWidget(
        ThemeScope(
          notifier: themeService,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => abrirAjustes(context),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.text('Mis facturas'), findsOneWidget);
      expect(find.byKey(const Key('ajustes-mis-facturas')), findsOneWidget);

      // El tema y el cierre de sesión siguen donde estaban.
      expect(find.byKey(const Key('ajustes-tema-oscuro')), findsOneWidget);
      expect(find.byKey(const Key('ajustes-cerrar-sesion')), findsOneWidget);
    });
  });
}

/// Comercio de prueba: no hace falta ninguno, el permiso de ubicación se
/// deniega y la lista nunca se pide.
class _ComerciosVacios extends ComerciosService {
  @override
  Future<List<Comercio>> listar({
    String? categoria,
    String? busqueda,
    bool? conPromociones,
    double? lat,
    double? lng,
  }) async {
    return [];
  }
}

/// Sesión de mentira: no toca el almacenamiento seguro ni la red.
class _AuthFalso extends AuthService {
  @override
  Future<String?> getAccessToken() async => 'token-de-prueba';
}

/// FacturasService que devuelve una sola factura, sin tocar la red.
class _FacturasFalsas extends FacturasService {
  @override
  Future<List<Factura>> listarMisFacturas({String? token}) async {
    return [
      Factura(
        id: 42,
        estado: 'aprobada',
        numeroFactura: '001-001-00000042',
        rucEmisor: '1790012345001',
        fechaFactura: '2026-03-15',
        montoTotal: 12.5,
        nivelVerificacion: 1,
      ),
    ];
  }
}
