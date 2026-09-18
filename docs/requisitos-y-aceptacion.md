# Requisitos y criterios de aceptación

> Estado al 2026-09-18. Basado en código existente, no en wishful thinking.

## Actores

| Actor | Descripción |
|-------|-------------|
| **Cliente** | Usuario final que busca comercios y registra compras para obtener descuentos |
| **Negocio** | Comercio afiliado que aparece en el directorio y ofrece descuentos |
| **Organizador** | Gestiona eventos y promociones especiales |

---

## Flujo: Auth (registro + login)

| # | Requisito | Estado | Criterio de aceptación |
|---|-----------|--------|------------------------|
| A1 | Registro con email, password, nombre, rol | ✅ Implementado | POST `/auth/registro` crea usuario en D1, retorna tokens JWT |
| A2 | Login con email y password | ✅ Implementado | POST `/auth/login` valida credenciales, retorna access_token + refresh_token |
| A3 | Refresh de access token | ✅ Implementado | POST `/auth/refresh` emite nuevo access_token con refresh_token válido |
| A4 | Tokens almacenados de forma segura en Flutter | ✅ Implementado | flutter_secure_storage guarda tokens, sesión persiste al cerrar/reabrir app |
| A5 | Rol inválido rechazado | ✅ Implementado | Solo acepta "cliente", "negocio", "organizador" |

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
| D7 | Buscar comercios por texto | ⏳ Pendiente | Filtrado local o por query param en el backend |
| D8 | Geolocalización / mapa | ⏳ Pendiente | Mostrar comercios cercanos en mapa |

---

## Flujo: Facturas (registro de compra)

| # | Requisito | Estado | Criterio de aceptación |
|---|-----------|--------|------------------------|
| F1 | Registrar compra con clave de acceso SRI (nivel 1) | ✅ Implementado | POST `/facturas/registrar` valida checksum, consulta SRI, guarda en D1 |
| F2 | Listar mis facturas | ✅ Implementado | GET `/facturas/mias` retorna facturas del usuario autenticado |
| F3 | Verificación SRI deshabilitable | ✅ Implementado | Variable `SRI_ENFORCE_VALIDATION` controla si se valida o solo se captura |
| F4 | UI de registro de compra en Flutter | ⏳ Pendiente | Pantalla para ingresar clave de acceso o datos de factura |
| F5 | Historial de compras en Flutter | ⏳ Pendiente | Lista de facturas del usuario con estado |

---

## Flujo: Negocio (gestión de comercio)

| # | Requisito | Estado | Criterio de aceptación |
|---|-----------|--------|------------------------|
| N1 | Registro como negocio crea comercio automáticamente | ✅ Implementado | Al registrar con rol "negocio", se crea entrada en tabla `comercios` |
| N2 | Editar perfil del comercio | ✅ Implementado | PUT `/comercios/:id` actualiza nombre, categoría, horario, foto |
| N3 | Ver facturas registradas en mi comercio | ⏳ Pendiente | Endpoint que liste facturas asociadas a un comercio |
| N4 | Gestionar descuentos | ⏳ Pendiente | CRUD de descuentos asociados a un comercio |

---

## Flujo: Organizador (eventos)

| # | Requisito | Estado | Criterio de aceptación |
|---|-----------|--------|------------------------|
| O1 | Crear eventos | ⏳ Pendiente | Endpoint y UI para crear eventos |
| O2 | Asociar comercios a eventos | ⏳ Pendiente | Relación evento-comercio |
| O3 | Gestionar promociones | ⏳ Pendiente | CRUD de promociones vinculadas a eventos |

---

## Flujo: Descuentos / Canje

| # | Requisito | Estado | Criterio de aceptación |
|---|-----------|--------|------------------------|
| C1 | Acumular descuentos por compras | ⏳ Pendiente | Lógica de negocio para calcular descuentos |
| C2 | Canjear descuento en un comercio | ⏳ Pendiente | Flujo de canje con validación |
| C3 | Ver saldo de descuentos | ⏳ Pendiente | UI que muestre descuentos disponibles |
