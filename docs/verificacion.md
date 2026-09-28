# Comandos de verificación

Comandos para correr cada verificación disponible en el proyecto.

Las cifras de abajo son las de la última corrida completa, medidas con estos mismos comandos. Si una cambia, hay que volver a medirlas; no vale dejarlas fijas en el documento.

## Backend (packages/backend)

```bash
# Typecheck — verifica que TypeScript compile sin errores
cd packages/backend && pnpm typecheck

# Tests — ejecuta todas las pruebas con Vitest (252 tests, 20 archivos)
cd packages/backend && pnpm test

# Build — genera el bundle para Workers (dry-run, no despliega)
cd packages/backend && pnpm build

# Deploy — sí despliega. Solo con autorización expresa.
cd packages/backend && pnpm deploy
```

## Flutter (apps/cliente_app)

```bash
# Analyze — verifica estáticos y lints del código Dart (32 avisos, 0 errores)
cd apps/cliente_app && flutter analyze

# Tests — ejecuta widget tests y unit tests (122 tests, 18 archivos)
cd apps/cliente_app && flutter test

# Solo un archivo
cd apps/cliente_app && flutter test test/cliente_hunt_test.dart
```

## Comprobaciones de migración

```bash
# Ver la última migración aplicada
cd packages/backend && wrangler d1 migrations list save-money-db

# Aplicar las que falten (solo con autorización)
cd packages/backend && wrangler d1 migrations apply save-money-db
```

La migración `0016_indices_frecuencia.sql` ya está aplicada en local y en remoto. Cualquier migración nueva debe seguir la numeración siguiente y volver a comprobarse con `EXPLAIN QUERY PLAN` sobre las consultas de frecuencia.

## Pruebas de mutación

Una prueba que no falla al romper el código a propósito no está vigilando nada. Estas son las mutaciones que se aplicaron y verificaron, con el resultado que deben dar.

### `verificarHorarioEvento` — `packages/backend/src/modules/antifraude/index.ts`

| Mutación | Resultado esperado |
|---|---|
| Volver a la implementación original con `new Date()` | Falla: se pierden los rechazos legítimos por día y mes invertidos |
| `new Date()` también para las fechas del evento | Falla: 6 pruebas |
| Comparar siempre por instante, ignorando que la fecha no traiga hora | Falla: 3 pruebas |
| Dejar que la fecha ilegible vuelva a pasar por `NaN` en vez de una rama explícita | Falla: 2 pruebas |

```bash
cd packages/backend
cp src/modules/antifraude/index.ts /tmp/anti.bak
# aplicar la mutación, correr pnpm test y contar los fallos con
#   pnpm test src/modules/antifraude 2>&1 | grep -cE "^\s+×"
cp /tmp/anti.bak src/modules/antifraude/index.ts
```

### Progreso de frecuencia en Flutter — `apps/cliente_app/lib/screens/hunt_screen.dart`

| Mutación | Resultado esperado |
|---|---|
| Dejar el botón siempre activo (`bloqueado = false`) | Falla la prueba del progreso con el botón bloqueado |
| Quitar la nota de facturas con fecha ilegible | Falla la prueba de la nota |

```bash
cd apps/cliente_app
cp lib/screens/hunt_screen.dart /tmp/hunt.bak
# aplicar la mutación, correr flutter test y confirmar que una prueba falla
cp /tmp/hunt.bak lib/screens/hunt_screen.dart
```

## Smoke tests (verificación rápida del backend desplegado)

```bash
# Health check
curl -s https://save-money-backend.iaalvearp.workers.dev/ | jq

# Listar comercios
curl -s https://save-money-backend.iaalvearp.workers.dev/comercios | jq '.comercios | length'

# Listar promociones Flash
curl -s https://save-money-backend.iaalvearp.workers.dev/flash/promociones | jq '.promociones | length'

# Listar eventos Hunt
curl -s https://save-money-backend.iaalvearp.workers.dev/hunt/eventos | jq '.eventos | length'
```

Las rutas de Hunt que exigen token no se pueden comprobar con `curl` sin uno. El progreso de frecuencia es de esas:

```bash
# Sin token debe responder 401
curl -s -o /dev/null -w '%{http_code}\n' \
  https://save-money-backend.iaalvearp.workers.dev/hunt/eventos/1/premios/1/progreso
```

## Pruebas visuales de pantallas (Flutter)

Pantallas que se deben revisar manualmente en emulador/dispositivo:

| Pantalla | Qué verificar |
|----------|--------------|
| `login_screen.dart` | Campos email/password, botón de entrada, navegación a registro |
| `registro_screen.dart` | Campos completos, checkbox consentimiento, validación edad |
| `home_screen.dart` | Lista de comercios, barra de búsqueda, chips categoría, botón "Cerca de mí", iconos Flash/Hunt |
| `comercio_detail_screen.dart` | Ficha completa, promociones, horario, mapa |
| `facturacion_screen.dart` | Campo clave 49 dígitos, indicador OCR, botón registrar |
| `historial_facturas_screen.dart` | Lista de facturas, pull-to-refresh, estados con colores |
| `ocr_capture_screen.dart` | Cámara, procesamiento OCR, vista previa texto, aviso si el permiso se deniega |
| `ocr_confirm_screen.dart` | Datos extraídos, confirmar/editar, enviar |
| `flash_screen.dart` | Lista de promociones, detalle, botón reclamar, aviso de ubicación denegada |
| `hunt_screen.dart` | Lista de eventos, detalle con rondas/premios/sponsors, comprar entrada |
| `hunt_screen.dart` (premio por frecuencia) | Barra de progreso, "Llevas X de Y compras", texto de la ventana, botón Reclamar activo o apagado, nota de facturas sin fecha legible |
| Aviso de notificaciones | Que sale una vez, que "Ahora no" no vuelve, que "Activar" pide el permiso, que no reaparece tras el tope |

El aviso de notificaciones solo se ve una vez por instalación según las preferencias guardadas. Para probarlo de nuevo hay que borrar los datos de la app o usar `FalsoPermisos` de `test/helpers/falso_permisos.dart` como base de una prueba.

## Resumen rápido

| Comando | Qué verifica | Ubicación | Último resultado |
|---------|-------------|-----------|------------------|
| `pnpm typecheck` | Tipos TypeScript | `packages/backend/` | ✅ 0 errores |
| `pnpm test` | Lógica de negocio | `packages/backend/` | ✅ 252/252, 20 archivos |
| `pnpm build` | Bundle Workers | `packages/backend/` | ✅ 171.08 KiB, gzip 36.50 KiB |
| `flutter analyze` | Calidad del código Dart | `apps/cliente_app/` | ⚠️ 0 errores, 32 avisos `info` |
| `flutter test` | Widgets y lógica | `apps/cliente_app/` | ✅ 122/122, 18 archivos |

Los 32 avisos de `flutter analyze` son lints de estilo (`use_null_aware_elements`, `prefer_function_declarations_over_variables`, `slash_for_doc_comments`) en código anterior. No son errores.
