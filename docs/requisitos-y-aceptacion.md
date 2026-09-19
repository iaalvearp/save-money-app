# Requisitos y criterios de aceptación

> Auditoría del estado real al 2026-09-18. Este documento se verificó leyendo el código actual del backend y de Flutter. ✅ significa código y contrato coherentes; ⚠️ significa implementación parcial o discrepancia entre capas; ⏳ significa que todavía no existe.

## Alcance y actores

| Actor | Alcance actual |
|---|---|
| Cliente | Registro, login, Discover, facturas, OCR local, challenge de nivel 3, Flash y consulta/compra de entradas Hunt |
| Negocio | Registro, comercio propio, promociones Flash y respuesta a invitaciones de patrocinio Hunt desde backend |
| Organizador | Eventos, rondas, premios, patrocinadores, entradas, entregas y cupones de consolación desde backend |
| Admin | Puede ejecutar operaciones protegidas por admin; no puede registrarse usando el endpoint público |

## Inventario real del backend

### Health

| Método | Ruta | Auth | Rol | Estado |
|---|---|---|---|---|
| GET | / | No | — | ✅ Existe; responde estado de la API |

### Auth — packages/backend/src/modules/auth/index.ts

| Método | Ruta | Auth | Rol | Estado |
|---|---|---|---|---|
| POST | /auth/registro | No | Registro permitido: cliente, negocio, organizador | ✅ Existe; admin no puede auto-registrarse |
| POST | /auth/login | No | — | ✅ Existe |
| POST | /auth/refresh | Refresh token en el body | Cualquier usuario con refresh válido | ✅ Existe |
| PATCH | /auth/consentimiento | Sí, Bearer | Cualquier rol autenticado | ✅ Backend; ⚠️ Flutter no envía token |

### Discover — packages/backend/src/modules/discover/index.ts

| Método | Ruta | Auth | Rol | Estado |
|---|---|---|---|---|
| GET | /comercios | No | — | ✅ Búsqueda, categoría, promociones y coordenadas opcionales |
| GET | /comercios/cercanos | No | — | ✅ Haversine con lat, lng y radio |
| GET | /comercios/:id | No | — | ✅ Detalle y promociones activas |
| POST | /comercios | Sí | negocio o admin | ✅ Existe |
| PUT | /comercios/:id | Sí | negocio o admin; el negocio debe ser dueño | ✅ Existe en backend |
| GET | /mis-comercios | Sí | negocio | ✅ Existe |

### Facturas — packages/backend/src/modules/facturas/index.ts

| Método | Ruta | Auth | Rol | Estado |
|---|---|---|---|---|
| POST | /facturas/challenge | Sí | cliente | ✅ Crea challenge de nivel 3 |
| POST | /facturas/registrar | Sí | cliente | ✅ Niveles 1, 2 OCR y 3 challenge |
| GET | /facturas/mias | Sí | cliente | ✅ Existe |

Notas:

- Nivel 1 usa checksum y consulta SRI según SRI_ENFORCE_VALIDATION.
- Nivel 2 recibe datos extraídos/confirmados, no el archivo de imagen.
- Nivel 3 recibe challenge, nonce y hash; no recibe la fotografía.
- En wrangler.toml, SRI_ENFORCE_VALIDATION está en "false"; la captura no funciona en modo estricto.

### SRI — packages/backend/src/modules/sri/index.ts

No hay endpoints HTTP /sri/*. SRI es una utilidad interna usada por Facturas: valida checksum y consulta el servicio externo SOAP.

### Antifraude — packages/backend/src/modules/antifraude/index.ts

No hay endpoints HTTP propios. Es una utilidad interna para duplicados SRI, duplicados de tickets, horario de eventos y consulta del estado que permite beneficios.

### Flash — packages/backend/src/modules/flash/index.ts

| Método | Ruta | Auth | Rol | Estado |
|---|---|---|---|---|
| GET | /flash/promociones | Sí | Cualquier rol autenticado | ✅ Existe |
| GET | /flash/promociones/:id | Sí | Cualquier rol autenticado | ✅ Existe |
| POST | /flash/promociones | Sí | negocio o admin | ✅ Existe |
| POST | /flash/promociones/:id/claim | Sí | Cualquier rol autenticado | ✅ Existe; es /claim, no /reclamar |
| GET | /flash/mis-cupones | Sí | Cualquier rol autenticado | ✅ Existe |
| POST | /flash/cupones/:id/canjear | Sí | negocio o admin; valida propiedad del comercio | ✅ Existe |

### Hunt — packages/backend/src/modules/hunt/index.ts

| Método | Ruta | Auth | Rol | Estado |
|---|---|---|---|---|
| GET | /hunt/eventos | Sí | Cualquier rol autenticado | ✅ Existe |
| GET | /hunt/eventos/:id | Sí | Cualquier rol autenticado | ✅ Existe |
| POST | /hunt/eventos | Sí | organizador o admin | ✅ Existe |
| POST | /hunt/eventos/:id/rondas | Sí | organizador o admin; propiedad del evento | ✅ Existe |
| POST | /hunt/eventos/:id/sponsors | Sí | organizador o admin; propiedad del evento | ✅ Existe |
| POST | /hunt/eventos/:eventoId/sponsors/:sponsorId/responder | Sí | negocio; valida comercio propietario | ✅ Existe |
| POST | /hunt/eventos/:id/premios | Sí | organizador o admin; propiedad del evento | ✅ Existe |
| POST | /hunt/eventos/:eventoId/premios/:premioId/entregar | Sí | organizador o admin | ✅ Existe |
| POST | /hunt/eventos/:eventoId/premios/:premioId/reclamar | Sí | Cualquier usuario autenticado | ✅ Existe |
| POST | /hunt/eventos/:id/entradas/comprar | Sí | Cualquier usuario autenticado | ✅ Existe |
| POST | /hunt/entradas/:id/comprobante | Sí | Cualquier usuario autenticado; solo su entrada | ✅ Existe |
| POST | /hunt/entradas/:id/revisar | Sí | organizador o admin; propiedad del evento | ✅ Existe |
| GET | /hunt/eventos/:eventoId/entradas | Sí | organizador o admin; propiedad del evento | ✅ Existe |
| POST | /hunt/eventos/:eventoId/cupones-consolacion | Sí | organizador o admin; propiedad del evento | ✅ Existe |

Hallazgo: el reclamo de premios existe, pero el código actual separa comprobaciones de duplicado/stock del INSERT; no debe documentarse como completamente atómico o protegido contra toda carrera.

### Lo que NO existe como módulo o ruta independiente

- No existe un módulo HTTP independiente /sri/*; SRI solo es utilidad interna.
- No existe un módulo independiente /cupones/*. Los cupones se manejan desde Flash y Hunt.
- Flash sí existe y tiene backend; no debe marcarse como inexistente.
- Hunt sí existe, incluidos eventos y entradas; no debe marcarse como inexistente.
- No se encontró endpoint separado para mapa, notificaciones push, panel administrativo completo ni subida de imágenes de tickets.

## Requisitos por flujo

### Auth

| # | Requisito | Estado | Evidencia / límite actual |
|---|---|---|---|
| A1 | Registro con email, password, nombre y rol | ✅ | /auth/registro; crea usuario y, para negocio, su comercio |
| A2 | Login | ✅ | /auth/login; devuelve access y refresh token |
| A3 | Renovación automática del access token | ⚠️ | /auth/refresh existe, pero Flutter no tiene método de refresh; main.dart conserva el TODO |
| A4 | Guardado seguro de tokens | ✅ | flutter_secure_storage |
| A5 | Rechazo de rol inválido | ⚠️ | Se rechazan roles desconocidos, pero admin tampoco está permitido en registro público |
| A6 | Consentimiento publicitario | ⚠️ | Backend existe; AuthService.actualizarConsentimiento no manda access token y falla con 401 |
| A7 | Protección de menores | ✅ | Backend y validación local exigen edad mínima para consentimiento publicitario |

### Discover

| # | Requisito | Estado | Evidencia / límite actual |
|---|---|---|---|
| D1 | Listar comercios | ✅ | GET /comercios y HomeScreen |
| D2 | Ver comercio por ID | ✅ | GET /comercios/:id y ComercioDetailScreen |
| D3 | Editar comercio | ⚠️ | Backend expone PUT; Flutter intenta PATCH y ApiClient no implementa put |
| D4 | Filtrar por categoría | ✅ | Query categoria |
| D5 | Lista Flutter | ✅ | Carga, error, vacío y refresh |
| D6 | Detalle Flutter | ✅ | Ficha y promociones activas |
| D7 | Buscar por texto | ✅ | Query q y barra de búsqueda |
| D8 | Cercanos/geolocalización | ⚠️ | Distancias y radio funcionan; no hay mapa y faltan declaraciones explícitas en manifiestos |
| D9 | Filtrar promociones | ✅ | Query con_promociones |

### Facturas

| # | Requisito | Estado | Evidencia / límite actual |
|---|---|---|---|
| F1 | Registrar por clave SRI | ✅ | /facturas/registrar, checksum y consulta configurable |
| F2 | Historial | ✅ | /facturas/mias y HistorialFacturasScreen |
| F3 | Validación SRI configurable | ⚠️ | El interruptor existe y está en false; el modo estricto aún no está activado |
| F4 | Registro manual/QR | ✅ | FacturacionScreen; QR y clave terminan en el mismo endpoint |
| F5 | Historial en Flutter | ✅ | Estados y pull-to-refresh |
| F6 | OCR de ticket | ✅ | OCR local; solo se envían datos confirmados, nunca la imagen |
| F7 | Nivel 3 challenge-response | ⚠️ | Challenge, nonce y hash son disuasivo; no prueban autenticidad criptográficamente y queda en revisión manual |
| F8 | Reintento SRI pendiente | ✅ | Reutiliza la fila pendiente y evita duplicarla |
| F9 | Persistencia de rechazos | ✅ | Conserva estado rechazada y motivo |

### Negocio

| # | Requisito | Estado | Evidencia / límite actual |
|---|---|---|---|
| N1 | Registro crea comercio | ✅ | Se crea comercio para rol negocio |
| N2 | Editar comercio | ⚠️ | Backend listo con PUT; Flutter usa método/ruta incorrectos |
| N3 | Patrocinar Hunt | ⚠️ | Backend tiene invitación y respuesta; Flutter no tiene flujo completo |
| N4 | Crear promociones Flash | ⚠️ | Backend tiene POST /flash/promociones; Flutter no tiene método ni pantalla |

### Organizador y Hunt

| # | Requisito | Estado | Evidencia / límite actual |
|---|---|---|---|
| O1 | Crear eventos | ⚠️ | Endpoint backend existe; Flutter solo lista/detalla/compra |
| O2 | Gestionar rondas | ⚠️ | Endpoint backend existe; no hay método ni UI Flutter |
| O3 | Gestionar premios | ⚠️ | Endpoint backend existe; no hay método ni UI Flutter |
| O4 | Revisar entradas | ⚠️ | Endpoint backend existe; el servicio tiene método, pero no envía token ni hay pantalla |
| O5 | Invitar patrocinadores | ⚠️ | Endpoint backend existe; no hay flujo Flutter completo |
| O6 | Emitir cupones de consolación | ⚠️ | Endpoint backend existe; no hay método/UI Flutter |
| O7 | Entregar premios | ⚠️ | Endpoint backend existe; no hay método/UI Flutter |
| O8 | Reclamar premios | ⚠️ | No hay reclamo en la UI; además la operación backend no es completamente atómica bajo carrera |

### Flash

| # | Requisito | Estado | Evidencia / límite actual |
|---|---|---|---|
| FL1 | Listar promociones | ⚠️ | Backend existe, pero FlashService no envía token y el backend exige autenticación |
| FL2 | Ver detalle | ⚠️ | Misma discrepancia de token |
| FL3 | Reclamar promoción | ⚠️ | Backend usa /claim; Flutter apunta a esa ruta, pero no envía token |
| FL4 | Cupón único | ⚠️ | Genera código único FLASH-...; no hay QR visual en pantalla Flash |
| FL5 | UI Flash | ⚠️ | Pantalla existe, pero sus llamadas autenticadas fallan por no enviar token |
| FL6 | Canjear cupón | ⚠️ | Backend existe; no hay método Flutter ni pantalla de negocio |

### Cupones

| # | Requisito | Estado | Evidencia / límite actual |
|---|---|---|---|
| C1 | Modelo/persistencia | ✅ | Tabla cupones y extensión Flash |
| C2 | Listar mis cupones | ⚠️ | Endpoint y método existen; no hay pantalla dedicada y falta token |
| C3 | Canjear cupón | ⚠️ | Endpoint existe; no hay flujo Flutter de negocio |
| C4 | Cupones Hunt/consolación | ⚠️ | Endpoint existe; no hay flujo Flutter para emitir o mostrar |

### Antifraude

| # | Requisito | Estado | Evidencia / límite actual |
|---|---|---|---|
| AF1 | Duplicados SRI | ✅ | Utilidad central usada por Facturas |
| AF2 | Duplicados de tickets | ✅ | Composite key y rechazo centralizado |
| AF3 | Horario del evento | ✅ | Utilidad de verificación |
| AF4 | Solo aprobadas generan beneficios | ⚠️ | estadoPermiteBeneficios devuelve solo estado aprobada; falta confirmar que todos los flujos la usen |
| AF5 | Reclamo atómico de premios | ⚠️ | Lecturas separadas antes de insertar |
| AF6 | Puntos aislados por evento | ✅ | UNIQUE (evento_id, usuario_id) |

## Inventario real de Flutter

### Servicios y endpoints que consumen

| Servicio | Método Flutter | Endpoint | ¿Existe? | Estado de integración |
|---|---|---|---|---|
| AuthService | registro | POST /auth/registro | Sí | ✅ Sin token, correcto |
| AuthService | login | POST /auth/login | Sí | ✅ Guarda tokens |
| AuthService | actualizarConsentimiento | PATCH /auth/consentimiento | Sí | ⚠️ No envía token |
| AuthService | refresh | — | Sí /auth/refresh | ⏳ No hay método Flutter |
| ComerciosService | listar | GET /comercios | Sí | ✅ Público |
| ComerciosService | cercanos | GET /comercios/cercanos | Sí | ✅ Público |
| ComerciosService | obtener | GET /comercios/:id | Sí | ✅ Público |
| ComerciosService | misComercios | GET /mis-comercios | Sí | ⚠️ No envía token |
| ComerciosService | crear | POST /comercios | Sí | ⚠️ No envía token |
| ComerciosService | actualizar | PATCH /comercios/:id | No | ❌ Backend solo expone PUT |
| FacturasService | registrar | POST /facturas/registrar | Sí | ✅ Envía token |
| FacturasService | registrarOCR | POST /facturas/registrar | Sí | ✅ Nivel 2 y sin imagen |
| FacturasService | crearChallenge | POST /facturas/challenge | Sí | ✅ Envía token |
| FacturasService | claimNivel3 | POST /facturas/registrar | Sí | ✅ Nivel 3 y token |
| FacturasService | listarMisFacturas | GET /facturas/mias | Sí | ✅ Envía token |
| OcrService | extraerDatos | Ninguno | — | ✅ OCR local; no sube fotografías |
| FlashService | listarPromociones | GET /flash/promociones | Sí | ⚠️ No envía token; recibe 401 |
| FlashService | obtenerPromocion | GET /flash/promociones/:id | Sí | ⚠️ No envía token; recibe 401 |
| FlashService | reclamarPromocion | POST /flash/promociones/:id/claim | Sí | ⚠️ Ruta correcta, sin token |
| FlashService | misCupones | GET /flash/mis-cupones | Sí | ⚠️ No envía token |
| HuntService | listarEventos | GET /hunt/eventos | Sí | ⚠️ No envía token; recibe 401 |
| HuntService | obtenerEvento | GET /hunt/eventos/:id | Sí | ⚠️ No envía token |
| HuntService | crearEvento | POST /hunt/eventos | Sí | ⚠️ No envía token; no hay pantalla |
| HuntService | comprarEntrada | POST /hunt/eventos/:id/entradas/comprar | Sí | ⚠️ No envía token |
| HuntService | listarEntradas | GET /hunt/eventos/:eventoId/entradas | Sí | ⚠️ No envía token; rol organizador/admin |
| HuntService | revisarEntrada | POST /hunt/entradas/:id/revisar | Sí | ⚠️ No envía token; no hay pantalla |

Métodos Hunt que no están en HuntService: crear rondas, premios, sponsors, respuesta del negocio, comprobante de entrada, entrega de premios, reclamo de premios y cupones de consolación.

### Pantallas existentes

| Archivo / pantalla | Servicio(s) | Endpoint detrás | Estado real |
|---|---|---|---|
| login_screen.dart — LoginScreen | AuthService | POST /auth/login | ✅ Coherente |
| registro_screen.dart — RegistroScreen | AuthService | POST /auth/registro | ✅ Coherente; consentimiento validado localmente |
| home_screen.dart — HomeScreen | ComerciosService, AuthService | GET /comercios, GET /comercios/cercanos | ✅ Rutas existentes; ubicación tiene límites abajo |
| comercio_detail_screen.dart — ComercioDetailScreen | ComerciosService | GET /comercios/:id | ✅ Coherente |
| facturacion_screen.dart — FacturacionScreen | FacturasService, lector QR local | POST /facturas/registrar | ✅ Coherente |
| historial_facturas_screen.dart — HistorialFacturasScreen | FacturasService | GET /facturas/mias | ✅ Coherente |
| ocr_capture_screen.dart — OcrCaptureScreen | OcrService, image_picker | Ninguno; procesamiento local | ✅ No sube imagen |
| ocr_confirm_screen.dart — OcrConfirmScreen | FacturasService | POST /facturas/registrar nivel 2 | ✅ Coherente |
| nivel3_capture_screen.dart — Nivel3CaptureScreen | FacturasService, OcrService | /facturas/challenge y /facturas/registrar | ✅ Endpoint existente; evidencia no criptográfica |
| flash_screen.dart — FlashScreen | FlashService | /flash/promociones | ⚠️ Existe; falta token |
| flash_screen.dart — _FlashDetalleScreen | FlashService | /flash/promociones/:id, /claim | ⚠️ Existe; falta token |
| hunt_screen.dart — HuntScreen | HuntService | /hunt/eventos | ⚠️ Existe; falta token |
| hunt_screen.dart — _EventoDetalleScreen | HuntService | /hunt/eventos/:id, /entradas/comprar | ⚠️ Existe; falta token |

Hay 11 archivos de pantalla y 13 clases widget contando las dos pantallas de detalle privadas. No hay pantalla dedicada de Mis cupones, canje, administración de comercio, organización Hunt ni revisión de entradas.

## Auditoría de geolocalización y permisos

### Paquetes

- apps/cliente_app/pubspec.yaml:40-41 declara geolocator: ^14.0.0 y permission_handler: ^11.3.1.
- No se encontró uso directo de permission_handler dentro de lib; el flujo usa APIs de Geolocator.

### HomeScreen

Archivo: apps/cliente_app/lib/screens/home_screen.dart:53-80.

1. Comprueba Geolocator.isLocationServiceEnabled().
2. Si el servicio está apagado, muestra Servicios de ubicación desactivados y termina.
3. Comprueba Geolocator.checkPermission().
4. Si está denegado, ejecuta Geolocator.requestPermission().
5. Si sigue denegado, muestra Permiso de ubicación denegado.
6. Si está denegado permanentemente, muestra Permiso de ubicación denegado permanentemente.
7. Si hay permiso, llama getCurrentPosition con alta precisión y timeout de 10 segundos.
8. Si falla la lectura, muestra No se pudo obtener la ubicación.
9. Si funciona, carga /comercios/cercanos y vuelve a cargar /comercios con lat y lng.

En apps/cliente_app/lib/screens/home_screen.dart:367-382 se muestra un banner naranja con botón Reintentar. No se encontró openAppSettings; si el permiso quedó permanentemente denegado, solo puede reintentarse desde la pantalla.

### FlashScreen

Archivo: apps/cliente_app/lib/screens/flash_screen.dart:2,34-38.

- Intenta Geolocator.getCurrentPosition con alta precisión y timeout de 5 segundos.
- No comprueba ni solicita permiso explícitamente.
- Si falla, continúa con lat y lng nulos y aun así llama a Flash; ubicación es opcional para ese servicio.

### Plataforma

- apps/cliente_app/android/app/src/main/AndroidManifest.xml no declara explícitamente ACCESS_FINE_LOCATION ni ACCESS_COARSE_LOCATION.
- apps/cliente_app/ios/Runner/Info.plist no contiene NSLocationWhenInUseUsageDescription ni NSLocationAlwaysAndWhenInUseUsageDescription.
- La lógica Dart existe, pero la configuración de permisos de plataforma queda incompleta/no verificada, especialmente para iOS.

### Backend geográfico

- Discover calcula distancia con Haversine en /comercios/cercanos y puede añadir distancia cuando /comercios recibe coordenadas.
- Flash puede filtrar por coordenadas y radio si el cliente las envía.
- No existe endpoint de mapa ni se encontró paquete de mapa en la app.

## Verificación de esta auditoría

| Comprobación | Resultado observado |
|---|---|
| pnpm run typecheck en packages/backend | ✅ 0 errores |
| pnpm run test en packages/backend | ✅ 110/110, 11 archivos |
| pnpm run build en packages/backend | ✅ 142.56 KiB / gzip 30.22 KiB |
| flutter analyze en apps/cliente_app | ⚠️ 0 errores, 17 avisos informativos |
| flutter test en apps/cliente_app | ✅ 18/18, 3 archivos |
| git diff --check | ✅ Sin errores de whitespace |

La auditoría no implementa correcciones. Las discrepancias ⚠️ quedan como trabajo posterior; no deben reinterpretarse como funcionalidades terminadas solo porque exista un endpoint backend o una pantalla Flutter.
