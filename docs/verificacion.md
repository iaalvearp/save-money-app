# Comandos de verificación

Comandos para correr cada verificación disponible en el proyecto.

## Backend (packages/backend)

```bash
# Typecheck — verifica que TypeScript compile sin errores
cd packages/backend && pnpm run typecheck

# Tests — ejecuta todas las pruebas con Vitest (110 tests, 11 archivos)
cd packages/backend && pnpm run test

# Build — genera el bundle para Workers (dry-run)
cd packages/backend && pnpm run build
```

## Flutter (apps/cliente_app)

```bash
# Analyze — verifica estáticos y lints del código Dart
cd apps/cliente_app && flutter analyze

# Tests — ejecuta widget tests y unit tests (18 tests, 3 archivos)
cd apps/cliente_app && flutter test
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
| `ocr_capture_screen.dart` | Cámara, procesamiento OCR, vista previa texto |
| `ocr_confirm_screen.dart` | Datos extraídos, confirmar/editar, enviar |
| `flash_screen.dart` | Lista de promociones, detalle, botón reclamar |
| `hunt_screen.dart` | Lista de eventos, detalle con rondas/premios/sponsors, comprar entrada |

## Resumen rápido

| Comando | Qué verifica | Ubicación |
|---------|-------------|-----------|
| `pnpm run typecheck` | Tipos TypeScript | `packages/backend/` |
| `pnpm run test` | 110 tests de lógica de negocio | `packages/backend/` |
| `pnpm run build` | Bundle Workers (142 KiB gzip 30 KiB) | `packages/backend/` |
| `flutter analyze` | Calidad del código Dart (0 errores) | `apps/cliente_app/` |
| `flutter test` | 18 tests de widgets y lógica | `apps/cliente_app/` |
