# Comandos de verificación

Comandos para correr cada verificación disponible en el proyecto.

## Backend (packages/backend)

```bash
# Typecheck — verifica que TypeScript compile sin errores
cd packages/backend && pnpm run typecheck

# Tests — ejecuta todas las pruebas con Vitest
cd packages/backend && pnpm run test

# Build — genera el bundle para Workers (dry-run)
cd packages/backend && pnpm run build
```

## Flutter (apps/cliente_app)

```bash
# Analyze — verifica estáticos y lints del código Dart
cd apps/cliente_app && flutter analyze

# Tests — ejecuta widget tests y unit tests
cd apps/cliente_app && flutter test
```

## Resumen rápido

| Comando | Qué verifica | Ubicación |
|---------|-------------|-----------|
| `pnpm run typecheck` | Tipos TypeScript | `packages/backend/` |
| `pnpm run test` | Lógica de negocio (checksum SRI, etc.) | `packages/backend/` |
| `flutter analyze` | Calidad del código Dart | `apps/cliente_app/` |
| `flutter test` | Widgets y lógica Flutter | `apps/cliente_app/` |
