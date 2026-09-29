import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cliente_app/screens/agregar_ronda_screen.dart';
import 'package:cliente_app/services/api_client.dart';
import 'package:cliente_app/services/auth_service.dart';
import 'package:cliente_app/services/hunt_service.dart';
import 'package:cliente_app/widgets/selector_fecha_hora.dart';

class _FakeAuth extends AuthService {
  @override
  Future<String?> getAccessToken() async => 'token-de-prueba';

  @override
  Future<String?> rolActual() async => 'organizador';

  @override
  Future<void> logout() async {}
}

HuntService _servicioHuntCon(MockClient mock) {
  return HuntService(
    api: ApiClient(baseUrl: 'http://test', httpClient: mock),
  );
}

void main() {
  group('AgregarRondaScreen', () {
    const inicioEvento = '2026-10-01 19:00:00';
    const finEvento = '2026-10-01 23:00:00';

    /// Calendario y reloj de mentira: cada pulsación devuelve el valor que le
    /// toca, y guarda lo que el widget le ofreció como rango.
    late List<DateTime> fechas;
    late List<TimeOfDay> horas;
    late List<List<DateTime>> rangos;

    PedirFecha pedirFechaDePrueba() {
      return (context, inicial, primero, ultimo) async {
        rangos.add([primero, ultimo]);
        return fechas.removeAt(0);
      };
    }

    PedirHora pedirHoraDePrueba() {
      return (context, inicial) async => horas.removeAt(0);
    }

    setUp(() {
      fechas = [];
      horas = [];
      rangos = [];
    });

    Future<void> pump(WidgetTester tester, MockClient mock) {
      return tester.pumpWidget(
        MaterialApp(
          home: AgregarRondaScreen(
            eventoId: 42,
            fechaInicio: inicioEvento,
            fechaFin: finEvento,
            servicio: _servicioHuntCon(mock),
            auth: _FakeAuth(),
            pedirFecha: pedirFechaDePrueba(),
            pedirHora: pedirHoraDePrueba(),
          ),
        ),
      );
    }

    Future<void> elegir(WidgetTester tester, String etiqueta) async {
      await tester.ensureVisible(find.widgetWithText(TextFormField, etiqueta));
      await tester.tap(find.widgetWithText(TextFormField, etiqueta));
      await tester.pumpAndSettle();
    }

    String texto(WidgetTester tester, String etiqueta) {
      return tester
          .widget<TextFormField>(find.widgetWithText(TextFormField, etiqueta))
          .controller!
          .text;
    }

    testWidgets('elige fecha y hora y envía la ronda con ese texto',
        (WidgetTester tester) async {
      String? cuerpo;
      String? ruta;
      final mock = MockClient((request) async {
        ruta = request.url.path;
        cuerpo = request.body;
        return http.Response('{"ronda": {"id": 9}}', 201,
            headers: {'content-type': 'application/json'});
      });

      await pump(tester, mock);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre'),
        'Primera ronda',
      );

      fechas.addAll([DateTime(2026, 10, 1), DateTime(2026, 10, 1)]);
      horas.addAll([
        const TimeOfDay(hour: 20, minute: 0),
        const TimeOfDay(hour: 21, minute: 0),
      ]);

      await elegir(tester, 'Hora de inicio');
      await elegir(tester, 'Hora de fin');

      expect(texto(tester, 'Hora de inicio'), '2026-10-01 20:00:00');
      expect(texto(tester, 'Hora de fin'), '2026-10-01 21:00:00');

      await tester.ensureVisible(find.text('Crear ronda'));
      await tester.tap(find.text('Crear ronda'));
      await tester.pumpAndSettle();

      expect(ruta, '/hunt/eventos/42/rondas');
      expect(cuerpo, contains('"nombre":"Primera ronda"'));
      expect(cuerpo, contains('"hora_inicio":"2026-10-01 20:00:00"'));
      expect(cuerpo, contains('"hora_fin":"2026-10-01 21:00:00"'));
    });

    testWidgets('la ronda no puede empezar antes de que empiece el evento',
        (WidgetTester tester) async {
      final mock = MockClient((request) async {
        return http.Response('{"error": "no"}', 400,
            headers: {'content-type': 'application/json'});
      });

      await pump(tester, mock);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre'),
        'Primera ronda',
      );

      // El widget acota el calendario a la ventana del evento.
      fechas.add(DateTime(2026, 10, 1));
      horas.add(const TimeOfDay(hour: 20, minute: 0));
      await elegir(tester, 'Hora de inicio');

      expect(texto(tester, 'Hora de inicio'), '2026-10-01 20:00:00');
      expect(rangos.single, [
        DateTime.parse(inicioEvento),
        DateTime.parse(finEvento),
      ]);

      // Ni el calendario ni el reloj ofrecen antes del inicio de la ronda,
      // que ahora es 20:00, más tarde que el inicio del evento.
      fechas.add(DateTime(2026, 10, 1));
      horas.add(const TimeOfDay(hour: 20, minute: 0));
      await elegir(tester, 'Hora de fin');

      expect(rangos.last.first, DateTime(2026, 10, 1, 20, 0));
      expect(texto(tester, 'Hora de fin'), '2026-10-01 20:00:00');
    });

    testWidgets('el fin no puede quedar antes que el inicio de la ronda',
        (WidgetTester tester) async {
      var peticiones = 0;
      final mock = MockClient((request) async {
        peticiones++;
        return http.Response('{"error": "no"}', 400,
            headers: {'content-type': 'application/json'});
      });

      await pump(tester, mock);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre'),
        'Primera ronda',
      );

      // Inicio 21:00, y el reloj del fin devuelve 20:00 en el mismo día.
      fechas.addAll([DateTime(2026, 10, 1), DateTime(2026, 10, 1)]);
      horas.addAll([
        const TimeOfDay(hour: 21, minute: 0),
        const TimeOfDay(hour: 20, minute: 0),
      ]);

      await elegir(tester, 'Hora de inicio');
      await elegir(tester, 'Hora de fin');

      // Queda clavado en el inicio de la ronda, no antes.
      expect(texto(tester, 'Hora de fin'), '2026-10-01 21:00:00');

      await tester.ensureVisible(find.text('Crear ronda'));
      await tester.tap(find.text('Crear ronda'));
      await tester.pumpAndSettle();

      expect(
        find.text('El fin de la ronda debe ser posterior al inicio'),
        findsOneWidget,
      );
      expect(peticiones, 0);
    });

    testWidgets('no deja elegir el fin después del fin del evento',
        (WidgetTester tester) async {
      await pump(
        tester,
        MockClient((request) async => http.Response('{}', 400,
            headers: {'content-type': 'application/json'})),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre'),
        'Primera ronda',
      );

      // Fin del evento: 23:00. Se piden las 23:30 y se recorta.
      fechas.addAll([DateTime(2026, 10, 1), DateTime(2026, 10, 1)]);
      horas.addAll([
        const TimeOfDay(hour: 21, minute: 0),
        const TimeOfDay(hour: 23, minute: 30),
      ]);

      await elegir(tester, 'Hora de inicio');
      await elegir(tester, 'Hora de fin');

      expect(texto(tester, 'Hora de fin'), finEvento);
    });
  });
}
