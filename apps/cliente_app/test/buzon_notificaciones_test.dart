import 'dart:async';
import 'dart:convert';

import 'package:cliente_app/services/notificaciones_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// La clave con la que el buzón se guarda en el dispositivo. Va escrita aquí a
/// mano para poder simular el paso del tiempo: un aviso de hace cuatro días solo
/// se puede construir si se edita lo que quedó guardado, porque el servicio
/// fecha los avisos al recibirlos.
const _claveBuzon = 'notificaciones_buzon';

RemoteMessage _mensaje({
  String? id = 'msg-1',
  String titulo = 'Empezó un Hunt',
  String cuerpo = 'El evento ya está en marcha',
  Map<String, String> data = const {'tipo': 'hunt_inicio'},
  DateTime? enviada,
}) {
  return RemoteMessage(
    messageId: id,
    data: data,
    notification: RemoteNotification(title: titulo, body: cuerpo),
    sentTime: enviada,
  );
}

/// Escribe avisos con fecha en el pasado, saltándose el servicio.
Future<void> _dejarEnElDispositivo(List<Map<String, dynamic>> avisos) async {
  SharedPreferences.setMockInitialValues({_claveBuzon: jsonEncode(avisos)});
}

Map<String, dynamic> _avisoJson({
  required String id,
  required String titulo,
  required DateTime fecha,
  bool leida = false,
  String cuerpo = 'cuerpo',
  Map<String, String> data = const {'tipo': 'prueba'},
}) {
  return {
    'id': id,
    'titulo': titulo,
    'cuerpo': cuerpo,
    'data': data,
    'fecha': fecha.toIso8601String(),
    'leida': leida,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('el buzón guarda y vuelve a leer', () {
    test('un aviso registrado sobrevive a cerrar la app', () async {
      final servicio = NotificacionesService();
      await servicio.cargar();
      await servicio.registrarMensaje(
        _mensaje(titulo: 'Empezó un Hunt', cuerpo: 'Corre que empieza'),
      );

      // Instancia nueva: es lo que pasa al reabrir la app.
      final otro = NotificacionesService();
      await otro.cargar();

      expect(otro.lista, hasLength(1));
      expect(otro.lista.single.titulo, 'Empezó un Hunt');
      expect(otro.lista.single.cuerpo, 'Corre que empieza');
      expect(otro.lista.single.leida, isFalse);
    });

    test('conserva el data del backend para poder abrir el destino', () async {
      final servicio = NotificacionesService();
      await servicio.cargar();
      await servicio.registrarMensaje(
        _mensaje(data: const {'tipo': 'premio_ganado', 'evento_id': '42'}),
      );

      final otro = NotificacionesService();
      await otro.cargar();

      expect(otro.lista.single.data, {
        'tipo': 'premio_ganado',
        'evento_id': '42',
      });
    });

    test('la lista va de la más reciente a la más antigua', () async {
      // Fechas relativas: en un mes de ahora las fijas ya habrian caducado y
      // la purga de 72h las borraria, que no es lo que se esta probando.
      final ahora = DateTime.now();
      await _dejarEnElDispositivo([
        _avisoJson(
          id: 'viejo',
          titulo: 'old',
          fecha: ahora.subtract(const Duration(hours: 3)),
        ),
        _avisoJson(
          id: 'nuevo',
          titulo: 'new',
          fecha: ahora.subtract(const Duration(hours: 1)),
        ),
        _avisoJson(
          id: 'medio',
          titulo: 'mid',
          fecha: ahora.subtract(const Duration(hours: 2)),
        ),
      ]);

      final servicio = NotificacionesService();
      await servicio.cargar();

      expect(servicio.lista.map((n) => n.titulo), ['new', 'mid', 'old']);
    });

    test('un buzón ilegible no deja la app sin abrir', () async {
      SharedPreferences.setMockInitialValues({_claveBuzon: 'no es json'});

      final servicio = NotificacionesService();
      await servicio.cargar();

      // Mejor perder los avisos que dejar la pantalla en blanco sin explicación.
      expect(servicio.lista, isEmpty);
    });
  });

  group('lo que caducó se limpia, lo reciente no', () {
    test('al abrir se borra lo que tiene más de 72 horas', () async {
      final ahora = DateTime.now();
      await _dejarEnElDispositivo([
        _avisoJson(
          id: 'caducado',
          titulo: ' Promoción de ayer pasado',
          fecha: ahora.subtract(const Duration(hours: 73)),
        ),
        _avisoJson(
          id: 'reciente',
          titulo: 'Promoción de hace un rato',
          fecha: ahora.subtract(const Duration(hours: 2)),
        ),
      ]);

      final servicio = NotificacionesService();
      await servicio.cargar();

      // Una promoción que ya terminó no informa de nada, y ocupa sitio.
      expect(servicio.lista.map((n) => n.titulo), [
        'Promoción de hace un rato',
      ]);
    });

    test('la limpieza también se guarda en el dispositivo', () async {
      await _dejarEnElDispositivo([
        _avisoJson(
          id: 'caducado',
          titulo: 'viejo',
          fecha: DateTime.now().subtract(const Duration(days: 5)),
        ),
      ]);

      final servicio = NotificacionesService();
      await servicio.cargar();
      await servicio.borrarTodas();

      // Si solo se borrara en memoria, el aviso Caducado volvería al abrir.
      final otro = NotificacionesService();
      await otro.cargar();
      expect(otro.lista, isEmpty);
    });

    test('justo dentro de la ventana se conserva', () async {
      await _dejarEnElDispositivo([
        _avisoJson(
          id: 'al_borde',
          titulo: 'al borde',
          fecha: DateTime.now().subtract(const Duration(hours: 71)),
        ),
      ]);

      final servicio = NotificacionesService();
      await servicio.cargar();

      expect(servicio.lista, hasLength(1));
    });
  });

  group('lo no leído', () {
    test('se cuenta y baja al marcar', () async {
      final servicio = NotificacionesService();
      await servicio.cargar();
      await servicio.registrarMensaje(_mensaje(id: 'a'));
      await servicio.registrarMensaje(_mensaje(id: 'b'));

      expect(servicio.noLeidas, 2);

      await servicio.marcarLeida(servicio.lista.first.id);

      expect(servicio.noLeidas, 1);
    });

    test('marcar como leída no borra el aviso', () async {
      final servicio = NotificacionesService();
      await servicio.cargar();
      await servicio.registrarMensaje(_mensaje(id: 'a'));

      await servicio.marcarLeida(servicio.lista.first.id);

      // Se puede querer volver a consultarlo.
      expect(servicio.lista, hasLength(1));
      expect(servicio.lista.single.leida, isTrue);
    });

    test('marcar todas deja todos, pero leídos', () async {
      final servicio = NotificacionesService();
      await servicio.cargar();
      await servicio.registrarMensaje(_mensaje(id: 'a'));
      await servicio.registrarMensaje(_mensaje(id: 'b'));

      await servicio.marcarTodasLeidas();

      expect(servicio.lista, hasLength(2));
      expect(servicio.noLeidas, 0);

      final otro = NotificacionesService();
      await otro.cargar();
      expect(otro.noLeidas, 0);
    });

    test('borrar todas vacía el buzón y el contador', () async {
      final servicio = NotificacionesService();
      await servicio.cargar();
      await servicio.registrarMensaje(_mensaje(id: 'a'));

      await servicio.borrarTodas();

      expect(servicio.lista, isEmpty);
      expect(servicio.noLeidas, 0);

      final otro = NotificacionesService();
      await otro.cargar();
      expect(otro.lista, isEmpty);
    });
  });

  group('los tres caminos de llegada de Firebase', () {
    late StreamController<RemoteMessage> alRecibir;
    late StreamController<RemoteMessage> alAbrir;

    setUp(() {
      alRecibir = StreamController<RemoteMessage>();
      alAbrir = StreamController<RemoteMessage>();
    });

    tearDown(() async {
      await alRecibir.close();
      await alAbrir.close();
    });

    test('con la app abierta, el aviso entra sin leer', () async {
      final servicio = NotificacionesService(
        alRecibirMensaje: alRecibir.stream,
        alAbrirMensaje: alAbrir.stream,
        mensajeInicial: () async => null,
      );
      await servicio.cargar();
      await servicio.escucharMensajes();

      alRecibir.add(_mensaje(titulo: 'Entró tu participación'));
      await pumpEventQueue();

      expect(servicio.lista.single.titulo, 'Entró tu participación');
      expect(servicio.noLeidas, 1);
    });

    test('si lo tocó con la app en segundo plano, entra leído', () async {
      final servicio = NotificacionesService(
        alRecibirMensaje: alRecibir.stream,
        alAbrirMensaje: alAbrir.stream,
        mensajeInicial: () async => null,
      );
      await servicio.cargar();
      await servicio.escucharMensajes();

      alAbrir.add(_mensaje(titulo: 'Ganaste un premio'));
      await pumpEventQueue();

      // Ya lo vio al tocarlo: dejarlo sin leer sería un contador que no baja.
      expect(servicio.lista.single.leida, isTrue);
      expect(servicio.noLeidas, 0);
    });

    test(
      'abrir la app desde el aviso con la app cerrada también lo marca',
      () async {
        final servicio = NotificacionesService(
          alRecibirMensaje: alRecibir.stream,
          alAbrirMensaje: alAbrir.stream,
          mensajeInicial: () async => _mensaje(titulo: 'Había una promo cerca'),
        );
        await servicio.cargar();
        await servicio.escucharMensajes();

        // Con la app cerrada no hay stream al que suscribirse: llega suelto.
        expect(servicio.lista.single.titulo, 'Había una promo cerca');
        expect(servicio.lista.single.leida, isTrue);
      },
    );

    test('sin mensaje inicial no inventa ninguno', () async {
      final servicio = NotificacionesService(
        alRecibirMensaje: alRecibir.stream,
        alAbrirMensaje: alAbrir.stream,
        mensajeInicial: () async => null,
      );
      await servicio.cargar();
      await servicio.escucharMensajes();

      expect(servicio.lista, isEmpty);
    });

    test('dos avisos del mismo tipo seguidos no se pisan', () async {
      final servicio = NotificacionesService(
        alRecibirMensaje: alRecibir.stream,
        alAbrirMensaje: alAbrir.stream,
        mensajeInicial: () async => null,
      );
      await servicio.cargar();
      await servicio.escucharMensajes();

      // Mismo messageId, como hace el backend con el mismo tipo de aviso.
      alRecibir.add(_mensaje(id: 'mismo', titulo: 'primero'));
      await pumpEventQueue();
      alRecibir.add(_mensaje(id: 'mismo', titulo: 'segundo'));
      await pumpEventQueue();

      expect(servicio.lista, hasLength(2));
      expect(servicio.lista.map((n) => n.titulo), ['segundo', 'primero']);
    });
  });
}
