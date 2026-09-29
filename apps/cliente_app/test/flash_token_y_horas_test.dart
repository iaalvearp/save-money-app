import 'dart:convert';

import 'package:cliente_app/services/api_client.dart';
import 'package:cliente_app/services/auth_service.dart';
import 'package:cliente_app/services/flash_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _FakeAuth extends AuthService {
  _FakeAuth(this.token);

  final String? token;

  @override
  Future<String?> getAccessToken() async => token;

  @override
  Future<void> logout() async {}
}

/// Las dos filas que devolvio el backend desplegado con la sesion de prueba.
/// El texto es UTC sin zona, tal como lo escribio la app al crearlas.
const _pruebaTarde = '{"id": 4, "comercio_id": 5, "titulo": "Prueba Tarde",'
    ' "descripcion": null, "descuento_porcentaje": 25,'
    ' "inicia_en": "2026-09-29 20:12:24", "termina_en": "2026-09-30 20:12:24",'
    ' "latitud": null, "longitud": null, "radio_km": 5,'
    ' "categoria": "Cafeteria", "max_usuarios": null,'
    ' "usuarios_notificados": 0, "comercio_nombre": "PRUEBA Cafe Central"}';

const _prueba2x1 = '{"id": 3, "comercio_id": 5, "titulo": "PRUEBA 2x1 en cafes",'
    ' "descripcion": "Promocion de prueba", "descuento_porcentaje": 50,'
    ' "inicia_en": "2026-09-28 00:00:00", "termina_en": "2026-10-05 00:00:00",'
    ' "latitud": -2.1894, "longitud": -79.8891, "radio_km": 20,'
    ' "categoria": "Cafeteria", "max_usuarios": null, "usuarios_notificados": 0,'
    ' "comercio_nombre": "PRUEBA Cafe Central"}';

/// El mismo formato que usa la app al guardar, para no tener que escribir a
/// mano el texto UTC en cada caso.
String _enUtc(DateTime instante) =>
    instante.toIso8601String().replaceFirst('T', ' ').substring(0, 19);

PromocionFlash _promo({
  required DateTime inicia,
  required DateTime termina,
}) {
  return PromocionFlash(
    id: 1,
    comercioId: 5,
    titulo: 'PRUEBA',
    descuentoPorcentaje: 50,
    iniciaEn: _enUtc(inicia),
    terminaEn: _enUtc(termina),
  );
}

void main() {
  group('Flash pide el token por su cuenta', () {
    test('sin token en la llamada, usa el de la sesion', () async {
      String? autorizacion;
      final servicio = FlashService(
        auth: _FakeAuth('token-de-sesion'),
        api: ApiClient(
          baseUrl: 'http://test',
          httpClient: MockClient((request) async {
            autorizacion = request.headers['authorization'];
            return http.Response('{"promociones": []}', 200,
                headers: {'content-type': 'application/json'});
          }),
        ),
      );

      // Asi llama la pantalla: sin pasarle token.
      await servicio.listarPromociones(lat: -2.1894, lng: -79.8891);

      expect(autorizacion, 'Bearer token-de-sesion');
    });

    test('el backend contesta 401 si la peticion va sin token', () async {
      // El 401 era el sintoma: la lista llegaba vacia sin explicar nada.
      final servicio = FlashService(
        auth: _FakeAuth(null),
        api: ApiClient(
          baseUrl: 'http://test',
          httpClient: MockClient(
            (_) async => http.Response(
              '{"error":"Token de autenticacion requerido"}',
              401,
              headers: {'content-type': 'application/json'},
            ),
          ),
        ),
      );

      await expectLater(
        servicio.listarPromociones(lat: -2.1894, lng: -79.8891),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'status', 401),
        ),
      );
    });

    test('el token que trae quien llama tiene prioridad', () async {
      String? autorizacion;
      final servicio = FlashService(
        auth: _FakeAuth('token-de-sesion'),
        api: ApiClient(
          baseUrl: 'http://test',
          httpClient: MockClient((request) async {
            autorizacion = request.headers['authorization'];
            return http.Response('{"promociones": []}', 200,
                headers: {'content-type': 'application/json'});
          }),
        ),
      );

      await servicio.listarPromociones(token: 'token-explicito');

      expect(autorizacion, 'Bearer token-explicito');
    });

    test('los otros caminos autenticados tambien llevan token', () async {
      // reclamation y mis cupones tampoco lo pasaban, y son del mismo backend.
      final vistas = <String, String?>{};
      final servicio = FlashService(
        auth: _FakeAuth('token-de-sesion'),
        api: ApiClient(
          baseUrl: 'http://test',
          httpClient: MockClient((request) async {
            vistas[request.url.path] = request.headers['authorization'];
            return http.Response('{"promociones": [], "cupones": []}', 200,
                headers: {'content-type': 'application/json'});
          }),
        ),
      );

      await servicio.obtenerPromocion(3);
      await servicio.reclamarPromocion(3);
      await servicio.misCupones();

      expect(
        vistas.values,
        everyElement('Bearer token-de-sesion'),
        reason: 'estas rutas requieren sesion y salian sin ella',
      );
    });
  });

  group('las fechas se leen en UTC, no en hora local', () {
    // Estas tres comparan contra "ahora" en UTC. Leidas como hora local, en
    // Ecuador, una ventana abierta marcaba "Proximamente".

    test('una ventana abierta en UTC esta activa', () {
      final ahora = DateTime.now().toUtc();
      final promo = _promo(
        inicia: ahora.subtract(const Duration(hours: 1)),
        termina: ahora.add(const Duration(hours: 1)),
      );

      expect(promo.estaActiva, isTrue);
      expect(promo.estadoTexto, 'Activa');
    });

    test('una promocion que empieza dentro de una hora aun no esta activa', () {
      final ahora = DateTime.now().toUtc();
      final promo = _promo(
        inicia: ahora.add(const Duration(hours: 1)),
        termina: ahora.add(const Duration(hours: 2)),
      );

      expect(promo.estaActiva, isFalse);
      expect(promo.estadoTexto, 'Próximamente');
    });

    test('una promocion que termino hace una hora ya no esta activa', () {
      final ahora = DateTime.now().toUtc();
      final promo = _promo(
        inicia: ahora.subtract(const Duration(hours: 2)),
        termina: ahora.subtract(const Duration(hours: 1)),
      );

      expect(promo.estaActiva, isFalse);
      expect(promo.estadoTexto, 'Finalizada');
    });

    test('el inicio cuenta, igual que en el backend', () {
      // El SQL es `inicia_en <= ahora`, asi que una promo que empieza en este
      // instante ya se puede usar.
      final ahora = DateTime.now().toUtc();
      final promo = _promo(inicia: ahora, termina: ahora.add(const Duration(hours: 1)));

      expect(promo.estaActiva, isTrue);
    });

    test('las dos filas del caso real se leen y no se rompen', () {
      final promos = [
        PromocionFlash.fromJson(
          jsonDecode(_pruebaTarde) as Map<String, dynamic>,
        ),
        PromocionFlash.fromJson(
          jsonDecode(_prueba2x1) as Map<String, dynamic>,
        ),
      ];

      expect(promos, hasLength(2));
      expect(promos.first.titulo, 'Prueba Tarde');
      expect(promos.first.latitud, isNull);
      expect(promos.last.radioKm, 20);
    });
  });
}
