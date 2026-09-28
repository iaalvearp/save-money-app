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
| POST | /hunt/eventos/:id/iniciar | Sí | organizador o admin; propiedad del evento | ✅ Existe |
| POST | /hunt/eventos/:id/rondas | Sí | organizador o admin; propiedad del evento | ✅ Existe; exige fecha y hora completas |
| POST | /hunt/eventos/:id/sponsors | Sí | organizador o admin; propiedad del evento | ✅ Existe |
| POST | /hunt/eventos/:eventoId/sponsors/:sponsorId/responder | Sí | negocio; valida comercio propietario | ✅ Existe |
| POST | /hunt/eventos/:id/premios | Sí | organizador o admin; propiedad del evento | ✅ Existe; valida stock, ronda y criterio |
| GET | /hunt/eventos/:eventoId/premios/:premioId/progreso | Sí | Cualquier usuario autenticado | ✅ Existe; no exige entrada ni evento abierto |
| POST | /hunt/eventos/:eventoId/premios/:premioId/reclamar | Sí | Cualquier usuario autenticado | ✅ Existe; valida el criterio de frecuencia |
| POST | /hunt/eventos/:eventoId/premios/:premioId/entregar | Sí | organizador o admin | ✅ Existe |
| GET | /hunt/eventos/:eventoId/premios/:premioId/ganadores | Sí | organizador o admin | ✅ Existe |
| POST | /hunt/eventos/:id/entradas/comprar | Sí | Cualquier usuario autenticado | ✅ Existe |
| POST | /hunt/entradas/:id/comprobante | Sí | Cualquier usuario autenticado; solo su entrada | ✅ Existe |
| POST | /hunt/entradas/:id/revisar | Sí | organizador o admin; propiedad del evento | ✅ Existe |
| GET | /hunt/eventos/:eventoId/entradas | Sí | organizador o admin; propiedad del evento | ✅ Existe |
| GET | /hunt/eventos/:eventoId/participantes-sin-premio | Sí | organizador o admin | ✅ Existe |
| POST | /hunt/eventos/:eventoId/cupones-consolacion | Sí | organizador o admin; propiedad del evento | ✅ Existe |

Hallazgo: el reclamo de premios existe, pero el código actual separa comprobaciones de duplicado/stock del INSERT; no debe documentarse como completamente atómico o protegido contra toda carrera.

### Lo que NO existe como módulo o ruta independiente

- No existe un módulo HTTP independiente /sri/*; SRI solo es utilidad interna.
- No existe un módulo independiente /cupones/*. Los cupones se manejan desde Flash y Hunt.
- Flash sí existe y tiene backend; no debe marcarse como inexistente.
- Hunt sí existe, incluidos eventos y entradas; no debe marcarse como inexistente.
- No se encontró endpoint separado para mapa, notificaciones push, panel administrativo completo ni subida de imágenes de tickets.

## Lectura de fechas — packages/backend/src/lib/fechas.ts

Único lugar del backend donde se interpretan fechas. La app guarda cada fecha en un formato distinto según de dónde venga y el backend las recibe tal cual; ordenar esas cadenas de texto no respeta el orden real y no permite restar dos ventanas.

| Export | Para qué sirve | Devuelve |
|---|---|---|
| `instanteDeCompra` | Fechas con hora real, las del reloj de quien compró | Milisegundos desde epoch, o `null` |
| `diaComoCalendario` | Ventanas de negocio: evento y ronda | Minutos desde epoch **del mediodía**, o `null` |
| `esFechaLegible` | Si un valor se puede leer como fecha, sea del formato que sea | Booleano |
| `instanteEnVentana` | Si un instante cae dentro de una ventana | Booleano |
| `instanteEnTextoUtc` / `ahoraEnUtc` | Comparar contra la hora actual del servidor | Texto |
| `traeHora` | Si la fecha dice la hora, además del día | Booleano |

### Formatos aceptados

| Formato | Ejemplo | Viene de |
|---|---|---|
| ISO con `Z` u offset | `2026-03-01T10:00:00-05:00` | SRI |
| ISO sin zona | `2026-03-01 10:00:00` | App |
| Año-mes-día | `2026-03-01` | App |
| Día/mes/año | `01/03/2026` | OCR |
| Día-mes-año corto | `1-3-26` | Compra declarada |

Ecuador no aplica horario de verano, así que su offset es siempre `-05:00`. Las fechas sin zona se leen como hora de Ecuador. Los años de dos dígitos se expanden a `20XX`.

### Criterio de aceptación

| # | Requisito | Estado | Evidencia |
|---|---|---|---|
| F1 | Las ventanas de Hunt y el horario del evento usan el módulo de fechas | ✅ | `hunt/index.ts` y `antifraude/index.ts` importan de `lib/fechas` |
| F2 | Ventanas de evento y ronda contadas en días calendario de Ecuador | ✅ | `diaComoCalendario` usa el mediodía, para que ningún desfase mueva la fecha al día de al lado |
| F3 | Corrección del desfase de cinco horas en Hunt | ✅ | Antes la ronda "10:00–12:00" se comparaba contra instantes y se rechazaban compras válidas |
| F4 | Fechas ilegibles no se bloquean | ✅ | `instanteDeCompra` y `diaComoCalendario` devuelven `null`, y quien las usa decide; el conteo de frecuencia reporta cuántas facturas quedaron fuera |
| F5 | La app manda la fecha tal como la tiene y el backend la interpreta | ✅ | `FacturasService` no valida ni transforma la fecha; el módulo de fechas acepta los cinco formatos |
| F6 | Los demás módulos usan el módulo de fechas | ⚠️ | Ver pendiente abajo |

### Pendiente: comparaciones con `new Date()` fuera del módulo de fechas

Quedan cuatro módulos que interpretan fechas con `new Date()` en vez de usar `lib/fechas`. No se tocaron en esta tanda porque su alcance era otro, pero hay que anotarlos, y el primero es serio.

| Ubicación | Qué hace | Riesgo verificado |
|---|---|---|
| `modules/auth/index.ts:110-111` | `calcularEdad` compara `getFullYear()`, `getMonth()` y `getDate()` | **Bug confirmado de un año.** Esos getters dan la hora local del servidor. `new Date("2000-09-01")` es medianoche UTC, que en Ecuador es `1999-08-31 19:00`, así que el backend trata a quien nació el 1 de septiembre como nacido el 31 de agosto del año anterior. Quien nació el 1 de enero ve además el año retrocedido. Sirve para validar que sea mayor de 18 y para el consentimiento publicitario, así que el error va en la dirección de dejar pasar a un menor |
| `modules/flash/index.ts:172` | `termina_en` contra `inicia_en` | Rechaza la promoción si la fecha no es ISO; no distingue día de instante |
| `modules/flash/index.ts:269-273` | Ventana de una promoción | Mismo caso: no distingue día de instante |
| `modules/cupones/index.ts:125` | `expira_en` contra ahora | Un cupón puede vencer antes o tarde según de dónde venga la fecha |
| `modules/facturas/index.ts:122-123` | Vencimiento del challenge de nivel 3 | Mismo caso |

La client-side envía la fecha de nacimiento en ISO (`YYYY-MM-DD`, del selector nativo) y calcula la edad con `DateTime(anio, mes, dia)`, así que **la app no sufre el error**: el bug está solo en la validación del backend, que es la que debería mandar. La corrección es la misma de aquí: usar `diaComoCalendario` y comparar partes, no instantes, y decidir el mismo día-vs-instante que se decidió en el horario del evento.

## Corrección de verificarHorarioEvento

`verificarHorarioEvento` (`packages/backend/src/modules/antifraude/index.ts`) decide si una compra cae dentro de la ventana de su evento. La usan los tres puntos de `facturas/index.ts` donde se registra una compra.

El bug era doble, y por eso hacía falta probarlo por partes:

| Comportamiento anterior | Consecuencia |
|---|---|
| `new Date("15/09/2026")` da `NaN`, y toda comparación con `NaN` es falsa | La validación **pasaba siempre**: ningún evento podía rechazar una compra fuera de horario |
| `new Date("01/09/2026")` lo lee como **9 de enero**, porque asume formato americano mes/día | Una compra legítima del 1 de septiembre se **rechazaba** por estar "antes" del evento |

| # | Requisito | Estado | Evidencia |
|---|---|---|---|
| HF1 | Con hora, se comparan instantes | ✅ | Una compra de las 07:00 no es válida en un evento que abre a las 08:00, aunque sea del mismo día |
| HF2 | Solo con día, se comparan días calendario | ✅ | No se puede afirmar que una compra fue antes de algo que no se sabe a qué hora abre |
| HF3 | Fecha ilegible → `valido: true` mediante rama explícita | ✅ | Antes pasaba por accidente con `NaN`; ahora es una decisión documentada |
| HF4 | Sin `evento_id` → `valido: true`, como antes | ✅ | No se cambió ese camino |
| HF5 | Evento inexistente → `valido: false` | ✅ | Es un error de referencia, no un problema de fecha |
| HF6 | Evento con horario ilegible → `valido: true` | ✅ | Sin ventana conocida no se puede afirmar que una compra esté fuera |
| HF7 | No rellenar `facturas.evento_id` ni cambiar los llamadores | ✅ | Los tres llamadores de `facturas/index.ts` quedan intactos |

La decisión de no bloquear cuando la fecha no se puede leer es deliberada: bloquear a alguien por una fecha que el sistema no entiende sería rechazar una compra legítima, y la compra se aprueba igualmente por otros motivos.

## Premios por frecuencia

Un premio de tipo `frecuencia` se gana juntando un número de compras. `criterio_frecuencia` es ese número.

### Qué cuenta y qué no

| Regla | Detalle |
|---|---|
| Solo compras **aprobadas** | El conteo parte de facturas en estado `aprobada` |
| Solo en **comercios patrocinadores** del evento, con el sponsor aprobado | Se une `eventos_sponsors`; un comercio que no patrocina no suma, aunque la compra sea válida |
| La ventana es la **ronda** si el premio pertenece a una ronda; si no, la del **evento** | `ventanaDelPremio` decide; si la ventana no se puede leer, no se inventa una |
| El filtrado por fecha se hace en JavaScript, no en SQL | A propósito: el parseo de fechas y las ventanas en Ecuador no son comparaciones que el D1 pueda hacer bien |
| Facturas con fecha ilegible **no cuentan** pero **se reportan** | `sin_fecha_legible` dice cuántas son, para que el conteo bajo no parezca un error |
| Un premio sin ventana legible da cero y no se puede ganar | Se prefiere no regalar un premio por un dato que el sistema no entiende |

| # | Requisito | Estado | Evidencia |
|---|---|---|---|
| FR1 | `GET /hunt/eventos/:eventoId/premios/:premioId/progreso` expone el progreso | ✅ | Devuelve `compras`, `criterio`, `faltan`, `cumple`, `ventana` y `sin_fecha_legible` |
| FR2 | Ver el progreso no exige entrada ni evento abierto | ✅ | Es solo información; lo que decide es el reclamo |
| FR3 | Un premio sin `criterio_frecuencia` responde 422 en vez de un cero | ✅ | Un cero haría pensar que no ha comprado nada |
| FR4 | Reclamar valida el criterio en el servidor | ✅ | 422 con el número que hace falta: `Este premio se gana con N compras y llevas M` |
| FR5 | La app muestra el progreso de cada premio por frecuencia | ✅ | `hunt_screen.dart`: barra, `Llevas X de Y compras` y la ventana en letra pequeña |
| FR6 | El botón de reclamar se desactiva solo si ya se sabe que no cumple | ✅ | Mientras carga, o si la consulta falla, el botón queda activo: el backend sigue validando |
| FR7 | Si el progreso no se puede cargar, no se muestra barra | ✅ | Es peor dejar a alguien esperando que bloquearle por un dato que no llegó |
| FR8 | Se avisa cuántas facturas quedaron fuera por fecha ilegible | ✅ | `N factura(s) no se contaron porque no se pudo leer su fecha.` |
| FR9 | Los premios de otros tipos no cambian | ✅ | Ni se les pregunta el progreso, ni se les toca el diseño |
| FR10 | Un 422 en un premio no deja a los demás sin barra | ✅ | Los progresos se piden juntos pero se resuelven por separado |

## Aviso de notificaciones

`NotificacionesService` y el widget `aviso_permiso_notificaciones.dart` implementan un ciclo que ya no vuelve a molestar a quien dijo que no.

| Regla | Detalle |
|---|---|
| Se avisa al entrar a la app con sesión, y no antes | El widget envuelve la pantalla del rol en `role_navigation.dart`, así que nunca aparece sin sesión |
| **Ahora no** cierra el aviso para siempre | Se guarda `notificaciones_aviso_cerrado` |
| **Activar** pide el permiso y cierra el aviso | Pero solo si el sistema lo concede o lo deniega permanentemente |
| Un rechazo simple **no** cierra el aviso | El sistema puede volver a preguntar; el aviso queda disponible |
| Tope de 2 avisos por instalación | `maximoVecesAviso = 2`, contado con `notificaciones_aviso_veces` |
| El token FCM se registra **después** de decidir | Nunca se pide un token antes de que la persona haya dicho qué quiere |
| El permiso concedido no muestra más avisos | `debeMostrarAviso` es falso si ya está concedido |

| # | Requisito | Estado | Evidencia |
|---|---|---|---|
| N1 | El aviso no se repite indefinidamente | ✅ | Tope de 2 y cierre permanente |
| N2 | Un rechazo simple no cuenta como "ya me escribiste" | ✅ | El botón de activar sigue disponible |
| N3 | El token FCM se registra tras la decisión | ✅ | `registrarToken` se llama al cerrar el diálogo, no al abrirlo |
| N4 | Cerrar el diálogo sin decidir no lo marca como visto | ✅ | Solo cuenta cuando se elige una opción |

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
| AF3 | Horario del evento | ✅ | `verificarHorarioEvento`; compara por día o por instante según la fecha, y no bloquea si no se puede leer |
| AF4 | Solo aprobadas generan beneficios | ⚠️ | estadoPermiteBeneficios devuelve solo estado aprobada; falta confirmar que todos los flujos la usen |
| AF5 | Reclamo atómico de premios | ⚠️ | Lecturas separadas antes de insertar |
| AF6 | Puntos aislados por evento | ✅ | UNIQUE (evento_id, usuario_id) |

## Inventario real de Flutter

### Servicios y endpoints que consumen

| Servicio | Método Flutter | Endpoint | ¿Existe? | Estado de integración |
|---|---|---|---|---|
| AuthService | registro | POST /auth/registro | Sí | ✅ Sin token, correcto |
| AuthService | login | POST /auth/login | Sí | ✅ Guarda tokens |
| AuthService | refresh | POST /auth/refresh | Sí | ✅ Método propio; además `ApiClient` lo llama solo ante un 401 |
| AuthService | actualizarConsentimiento | PATCH /auth/consentimiento | Sí | ⚠️ Sigue sin enviar token |
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
| HuntService | listarEventos | GET /hunt/eventos | Sí | ✅ Envía token |
| HuntService | obtenerEvento | GET /hunt/eventos/:id | Sí | ✅ Envía token |
| HuntService | crearEvento | POST /hunt/eventos | Sí | ✅ Envía token; hay pantalla de creación |
| HuntService | comprarEntrada | POST /hunt/eventos/:id/entradas/comprar | Sí | ✅ Envía token |
| HuntService | listarEntradas | GET /hunt/eventos/:eventoId/entradas | Sí | ✅ Envía token; rol organizador/admin |
| HuntService | revisarEntrada | POST /hunt/entradas/:id/revisar | Sí | ✅ Envía token; hay pantalla de revisión |
| HuntService | reclamarPremio | POST /hunt/eventos/:eventoId/premios/:premioId/reclamar | Sí | ✅ Envía token |
| HuntService | progresoFrecuencia | GET /hunt/eventos/:eventoId/premios/:premioId/progreso | Sí | ✅ Envía token |

`HuntService` cubre además crear rondas, crear premios, invitar sponsor, subir comprobante, entregar premio, gananadores, participantes sin premio y emitir cupones de consolación. Ningún método de `HuntService` ni de `FlashService` se queda sin token; lo que no lo manda es la pantalla que los llama.

**Lo que sigue sin token:** `AuthService.actualizarConsentimiento` y todas las llamadas de `flash_screen.dart`.

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
| hunt_screen.dart — HuntScreen | HuntService | /hunt/eventos | ✅ Coherente |
| hunt_screen.dart — _EventoDetalleScreen | HuntService | /hunt/eventos/:id, /entradas/comprar, /premios/:id/progreso, /premios/:id/reclamar | ✅ Coherente; muestra el progreso de frecuencia |

Hay 29 archivos en `lib/screens` y 43 clases widget en `lib/` contando las pantallas privadas de detalle. Sí existen `canjear_cupon_screen.dart`, `cupon_consolacion_screen.dart`, `revision_entradas_screen.dart`, `mi_comercio_form_screen.dart`, `sponsors_screen.dart` y las de creación de evento, ronda, premio y promoción. No hay pantalla de administración general ni de mapa.

## Auditoría de geolocalización y permisos

### Paquetes

- apps/cliente_app/pubspec.yaml:40-41 declara geolocator: ^14.0.0 y permission_handler: ^11.3.1.
- `permission_handler` ya se usa en `lib`: `permiso_camara_service.dart` y `permiso_ubicacion_service.dart`, que exponen los estados del permiso y `openAppSettings()`. El resto de los flujos sigue con las APIs de Geolocator.

### HomeScreen

1. Comprueba Geolocator.isLocationServiceEnabled().
2. Si el servicio está apagado, muestra Servicios de ubicación desactivados y termina.
3. Pide el permiso con `solicitarPermisoUbicacion()` de `permiso_ubicacion_service.dart`.
4. Si está denegado, muestra Permiso de ubicación denegado y puede reintentarse.
5. Si está denegado permanentemente, ofrece abrir los ajustes.
6. Si hay permiso, llama getCurrentPosition con alta precisión y timeout de 10 segundos.
7. Si falla la lectura, muestra No se pudo obtener la ubicación, con un banner naranja y botón Reintentar.
8. Si funciona, carga /comercios/cercanos y vuelve a cargar /comercios con lat y lng.

### FlashScreen

Ya no depende solo de `Geolocator` con excepciones: usa `permiso_ubicacion_service.dart` y su propio aviso. Ver "Flash pide su propia ubicación" más abajo.

### Plataforma

Los cuatro permisos que la app necesita están declarados. Antes faltaban los de ubicación, y el backend ya exigía token en rutas geográficas.

| Permiso | Android (`AndroidManifest.xml`) | iOS (`Info.plist`) |
|---|---|---|
| Cámara | `android.permission.CAMERA` | `NSCameraUsageDescription` |
| Ubicación | `ACCESS_FINE_LOCATION` y `ACCESS_COARSE_LOCATION` | `NSLocationWhenInUseUsageDescription` |
| Notificaciones | `POST_NOTIFICATIONS` | No aplica clave de descripción |
| Fotos de la galería | — | `NSPhotoLibraryUsageDescription` |

### Cámara bajo demanda

`permiso_camara_service.dart` es el único que consulta el permiso, y lo comparte `facturacion_screen`, `ocr_capture_screen`, `nivel3_capture_screen` y `comprobante_entrada_screen`, además del aviso `aviso_permiso_camara.dart`.

| Regla | Detalle |
|---|---|
| Se pide cuando la pantalla necesita la cámara, no al arrancar | `solicitarPermisoCamara` solo consulta si el estado es `denied`; si nunca se preguntó, ahí lo pide |
| Elegir una foto de la galería no necesita cámara | `revisarPermisoParaCaptura(requiereCamara: false)` devuelve concedido sin tocar el sistema |
| Denegado permanentemente abre los ajustes | `abrirConfiguracion()` es el único camino para revertirlo; Android no deja volver a preguntar |
| Un rechazo simple deja poder reintentar | El estado `denegado` se distingue de `denegadoPermanente` |

### Flash pide su propia ubicación

`flash_screen.dart` no espera al permiso de la pantalla de inicio: llama a `solicitarPermisoUbicacion()` y distingue `denegado` de `denegadoPermanente`, y en ese caso ofrece abrir los ajustes. Si no hay permiso, sigue funcionando con `lat` y `lng` nulos, porque la ubicación es opcional para ese servicio.

### El reporte de ubicación solo comprueba

`reporte_ubicacion.dart` es el widget que reporta la posición para el disparador de "Flash por cercanía". **No es un servicio de seguimiento en segundo plano**: solo reacciona a que la app vuelva a primer plano y a un intervalo de 5 minutos mientras sigue visible, y se monta en `main.dart`.

Comprueba el permiso antes de tocar el GPS, y si falta, termina en silencio: no pide permiso con un diálogo ni interrumpe el uso de la app, porque el permiso se pide desde la pantalla que lo necesita. Un fallo de red o de señal también se traga, porque el reporte es opcional.

### HomeScreen y los ajustes del sistema

`home_screen.dart` ya no pide el permiso por su cuenta: usa `solicitarPermisoUbicacion()` y, si quedó denegado permanentemente, ofrece abrir los ajustes con `abrirConfiguracionUbicacion()`. La lógica de servicios apagados, timeout de 10 segundos y reintento se mantiene.

### Backend geográfico

- Discover calcula distancia con Haversine en /comercios/cercanos y puede añadir distancia cuando /comercios recibe coordenadas.
- Flash puede filtrar por coordenadas y radio si el cliente las envía.
- No existe endpoint de mapa ni se encontró paquete de mapa en la app.

## Verificación de esta auditoría

Cifras medidas en esta corrida, no copiadas de documentación anterior.

| Comprobación | Resultado observado |
|---|---|
| `pnpm typecheck` en packages/backend | ✅ 0 errores |
| `pnpm test` en packages/backend | ✅ 252/252, 20 archivos |
| `pnpm build` en packages/backend | ✅ 171.08 KiB / gzip 36.50 KiB |
| `flutter analyze` en apps/cliente_app | ⚠️ 0 errores, 32 avisos informativos |
| `flutter test` en apps/cliente_app | ✅ 122/122, 18 archivos |
| `git diff --check` | ✅ Sin errores de whitespace |

Los 32 avisos de `flutter analyze` son `info` de lints de estilo (`use_null_aware_elements`, `prefer_function_declarations_over_variables`, `slash_for_doc_comments`) en código anterior a esta tanda. Ninguno es un error ni un aviso de calidad que afecte al funcionamiento.

La auditoría no implementa correcciones por sí misma. Las discrepancias ⚠️ quedan como trabajo posterior; no deben reinterpretarse como funcionalidades terminadas solo porque exista un endpoint backend o una pantalla Flutter.
