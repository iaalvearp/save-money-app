# Requisitos y criterios de aceptación

> Estado al 2026-09-18. Basado en código existente y verificación automática (110 tests backend, 18 tests Flutter).

## Actores

| Actor | Descripción |
|-------|-------------|
| **Cliente** | Usuario final que busca comercios, registra compras y participa en eventos |
| **Negocio** | Comercio afiliado que aparece en el directorio, ofrece descuentos y patrocina eventos |
| **Organizador** | Gestiona eventos, rondas, premios, entradas y patrocinadores |

---

## Flujo: Auth (registro + login)

| # | Requisito | Estado | Criterio de aceptación |
|---|-----------|--------|------------------------|
| A1 | Registro con email, password, nombre, rol | ✅ Implementado | POST `/auth/registro` crea usuario en D1, retorna tokens JWT |
| A2 | Login con email y password | ✅ Implementado | POST `/auth/login` valida credenciales, retorna access_token + refresh_token |
| A3 | Refresh de access token | ✅ Implementado | POST `/auth/refresh` emite nuevo access_token con refresh_token válido |
| A4 | Tokens almacenados de forma segura en Flutter | ✅ Implementado | flutter_secure_storage guarda tokens, sesión persiste al cerrar/reabrir app |
| A5 | Rol inválido rechazado | ✅ Implementado | Solo acepta "cliente", "negocio", "organizador", "admin" |
| A6 | Consentimiento publicitario | ✅ Implementado | POST `/auth/consentimiento` actualiza consentimiento, fecha y edad |
| A7 | Protección de menores | ✅ Implementado | Registro con consentimiento requiere >= 18 años, validado backend + Flutter |

---

## Flujo: Discover (listado de comercios)

| # | Requisito | Estado | Criterio de aceptación |
|---|-----------|--------|------------------------|
| D1 | Listar comercios | ✅ Implementado | GET `/comercios` retorna lista con nombre, categoría, es_patrocinado |
| D2 | Obtener comercio por ID | ✅ Implementado | GET `/comercios/:id` retorna ficha completa (nombre, categoría, RUC, lat/lng, horario, foto) |
| D3 | Actualizar comercio (solo dueño o admin) | ✅ Implementado | PUT `/comercios/:id` con auth, verifica ownership |
| D4 | Filtrar por categoría | ✅ Implementado | GET `/comercios?categoria=X` filtra por categoría |
| D5 | UI de lista en Flutter | ✅ Implementado | HomeScreen muestra comercios con loading, error, empty state, pull-to-refresh |
| D6 | UI de detalle en Flutter | ✅ Implementado | ComercioDetailScreen muestra ficha completa con foto (o placeholder) |
| D7 | Buscar comercios por texto | ✅ Implementado | GET `/comercios?q=termino` búsqueda por nombre, barra de búsqueda en HomeScreen |
| D8 | Geolocalización / mapa | ✅ Implementado | GET `/comercios/cercanos` con Haversine, botón "Cerca de mí" en Flutter |
| D9 | Comercios con promociones destacados | ✅ Implementado | GET `/comercios?con_promociones=true`, indicador visual en HomeScreen |

---

## Flujo: Facturas (registro de compra)

| # | Requisito | Estado | Criterio de aceptación |
|---|-----------|--------|------------------------|
| F1 | Registrar compra con clave de acceso SRI (nivel 1) | ✅ Implementado | POST `/facturas/registrar` valida checksum, consulta SRI, guarda en D1 |
| F2 | Listar mis facturas | ✅ Implementado | GET `/facturas/mias` retorna facturas del usuario autenticado |
| F3 | Verificación SRI deshabilitable | ✅ Implementado | Variable `SRI_ENFORCE_VALIDATION` controla si se valida o solo se captura |
| F4 | UI de registro de compra en Flutter | ✅ Implementado | FacturacionScreen con campo clave de acceso, validación 49 dígitos, OCR |
| F5 | Historial de compras en Flutter | ✅ Implementado | HistorialFacturasScreen con pull-to-refresh, estados, colores |
| F6 | Registro nivel 2 (ticket físico + OCR) | ✅ Implementado | POST `/facturas/registrar` nivel 2, google_mlkit_text_recognition |
| F7 | Registro nivel 3 (challenge-response) | ✅ Implementado | POST `/facturas/challenge` + nonce +照片, estado pendiente_revision_nombre |
| F8 | Reintento SRI pendiente | ✅ Implementado | POST `/facturas/registrar` sobre factura pendiente reintenta consulta SRI |
| F9 | Persistencia de rechazos | ✅ Implementado | Facturas rechazadas se guardan con estado "rechazada" para auditoría |

---

## Flujo: Negocio (gestión de comercio)

| # | Requisito | Estado | Criterio de aceptación |
|---|-----------|--------|------------------------|
| N1 | Registro como negocio crea comercio automáticamente | ✅ Implementado | Al registrar con rol "negocio", se crea entrada en tabla `comercios` |
| N2 | Editar perfil del comercio | ✅ Implementado | PUT `/comercios/:id` actualiza nombre, categoría, horario, foto |
| N3 | Participar como patrocinador Hunt | ✅ Implementado | POST `/hunt/eventos/:id/sponsors` invita, negocio acepta/rechaza |
| N4 | Ofrecer promociones Flash | ✅ Implementado | A través de facturas aprobadas que generan cupones automáticos |

---

## Flujo: Organizador (eventos)

| # | Requisito | Estado | Criterio de aceptación |
|---|-----------|--------|------------------------|
| O1 | Crear eventos | ✅ Implementado | POST `/hunt/eventos` crea evento con fechas, nombre, precio entrada |
| O2 | Gestionar rondas | ✅ Implementado | POST `/hunt/eventos/:id/rondas` crea rondas con horarios |
| O3 | Gestionar premios | ✅ Implementado | POST `/hunt/eventos/:id/premios` crea premios con stock y tipo |
| O4 | Aprobar/rechazar entradas | ✅ Implementado | POST `/hunt/entradas/:id/revisar` con aprueba: true/false |
| O5 | Invitar patrocinadores | ✅ Implementado | POST `/hunt/eventos/:id/sponsors` con comercio_id |
| O6 | Emitir cupones de consolación | ✅ Implementado | POST `/hunt/eventos/:id/cupones-consolacion` con lista de usuarios |
| O7 | Entregar premios | ✅ Implementado | POST `/hunt/eventos/:eventoId/premios/:premioId/entregar` |
| O8 | Reclamar premios (cliente) | ✅ Implementado | POST `/hunt/eventos/:eventoId/premios/:premioId/reclamar` con validación atómica |

---

## Flujo: Flash (promociones relámpago)

| # | Requisito | Estado | Criterio de aceptación |
|---|-----------|--------|------------------------|
| FL1 | Listar promociones Flash | ✅ Implementado | GET `/flash/promociones` con filtros de categoría y ubicación |
| FL2 | Detalle de promoción | ✅ Implementado | GET `/flash/promociones/:id` retorna comercio, descuento, vigencia |
| FL3 | Reclamar promoción Flash | ✅ Implementado | POST `/flash/promociones/:id/reclamar` genera cupón automático |
| FL4 | Cupón con QR único | ✅ Implementado | Generación de código QR con prefijo FLASH, expiración 30 días |
| FL5 | UI de lista y detalle en Flutter | ✅ Implementado | FlashScreen con pull-to-refresh, detalle con mapa y reclamar |

---

## Flujo: Protección antifraude

| # | Requisito | Estado | Criterio de aceptación |
|---|-----------|--------|------------------------|
| AF1 | Detección de duplicados SRI | ✅ Implementado | `verificarDuplicadoSRI` rechaza misma clave por mismo usuario |
| AF2 | Detección de duplicados ticket | ✅ Implementado | `verificarDuplicadoTicket` rechaza ticket con mismos datos estructurados |
| AF3 | Verificación de horario de evento | ✅ Implementado | `verificarHorarioEvento` valida que factura esté dentro del rango del evento |
| AF4 | Control de estado para beneficios | ✅ Implementado | `estadoPermiteBeneficios` solo permite "aprobada" y "pendiente_verificacion_sri" |
| AF5 | Reclamo atómico de premios | ✅ Implementado | Stock, unicidad y puntos en operación atómica, race condition protegida |
| AF6 | Puntos aislados por evento | ✅ Implementado | `puntos_evento` con UNIQUE `(evento_id, usuario_id)`, sin cruce entre eventos |

---

## Resumen de verificación

| Categoría | Resultado |
|-----------|-----------|
| Backend typecheck | ✅ 0 errores |
| Backend tests | ✅ 110/110 (11 archivos) |
| Backend build | ✅ 142.56 KiB / gzip 30.22 KiB |
| Flutter analyze | ✅ Solo info (17 issues info, 0 errores) |
| Flutter tests | ✅ 18/18 (3 archivos) |
| Migraciones D1 | ✅ 0001-0009 |
| Módulos backend | ✅ auth, discover, facturas, flash, hunt, antifraude, sri |
| Pantallas Flutter | ✅ 11 pantallas |
| Servicios Flutter | ✅ 7 servicios |
