# Decisión: Módulo de Cupones

> Estado: 2026-09-18. Decisión tomada antes de implementación.

## Contexto

La tabla `cupones` existe desde la migración 0001 con estos campos:

```sql
cupones (
  id, comercio_id, cliente_id, codigo_qr UNIQUE,
  estado ('activo'|'utilizado'|'expirado'),
  descuento, expira_en, created_at
)
```

La tabla se creó como parte del modelo inicial sin un comportamiento de negocio definido. Esta decisión establece cómo se usará.

---

## Decisión

### ¿Pertenecen a Flash, Hunt o ambos?

**A ambos.** Se utiliza la misma tabla con un campo `tipo` que distingue el origen:

| Tipo | Descripción |
|------|-------------|
| `flash` | Descuento emitido por un comercio tras compra verificada |
| `hunt` | Premio de consolación emitido por un organizador de evento |

**Justificación:** Ambos tipos comparten la misma estructura (QR, expiración, estado, canje en comercio). Separarlos en dos tablas duplicaría lógica sin beneficio.

### ¿Quién los emite?

| Tipo | Emisor | Flujo |
|------|--------|-------|
| `flash` | El sistema (automático) | Al aprobarse una factura (estado `aprobada`), el sistema genera un cupón para el `comercio_id` de la factura |
| `hunt` | El organizador | Al finalizar una ronda de Hunt, el organizador asigna premios de consolación a participantes que no ganaron premio principal |

### ¿Quién los visualiza?

| Actor | Ve |
|-------|----|
| **Cliente** | Sus cupones activos (Flash y Hunt) en pantalla "Mis cupones" |
| **Negocio** | Cupones emitidos para su comercio (para validar canje) |
| **Organizador** | Cupones Hunt que él mismo emitió |

### ¿Cómo expiran?

| Tipo | Caducidad |
|------|-----------|
| `flash` | `expira_en` se calcula al emitir: `now + 30 días` (configurable) |
| `hunt` | `expira_en` se calcula al emitir: `now + fecha_fin del evento + 7 días` |

Si `expira_en` es NULL, el cupón no expira (no se recomienda).

Un cron job periódico (o la lógica al consultar) marca como `expirado` los cupones cuyo `expira_en < now()`.

### ¿Cómo se canjean sin aplicación de comercio?

El canje es **manual** basado en QR:

1. El cliente muestra el código QR de su cupón al cajero/dueño del comercio
2. El comercio valida visualmente el código
3. El comercio ingresa el código en su panel (o app) para marcar como `utilizado`
4. El sistema actualiza el estado a `utilizado` y registra `canjeado_en`

**No se requiere app del comercio para el canje inicial.** El comercio puede validar visualmente y reportar después.

### ¿Cómo se evita la reutilización?

| Mecanismo | Implementación |
|-----------|---------------|
| **QR único** | `codigo_qr TEXT UNIQUE` — ya existe en el schema |
| **Estado** | `estado = 'utilizado'` — un cupón utilizado no puede canjearse de nuevo |
| **Validación server-side** | Al canjear, el backend verifica: `estado = 'activo'` AND `expira_en > now()` |
| **Una vez por factura** | El cupón Flash se genera una sola vez por factura aprobada (el sistema no duplica) |

### ¿El QR será mostrado por el cliente?

**Sí.** El cliente ve su cupón en "Mis cupones", que muestra:
- Código QR (como imagen o string)
- Porcentaje de descuento
- Fecha de expiración
- Nombre del comercio

El comercio compara visualmente el código o lo ingresa manualmente para validar.

---

## Cambios necesarios en el schema

```sql
-- Agregar campo tipo al existing cupones table
ALTER TABLE cupones ADD COLUMN tipo TEXT NOT NULL DEFAULT 'flash'
  CHECK (tipo IN ('flash', 'hunt'));

-- Opcional: rastrear quién emitió y cuándo se canjeó
ALTER TABLE cupones ADD COLUMN emitido_por INTEGER REFERENCES usuarios(id);
ALTER TABLE cupones ADD COLUMN canjeado_en TEXT;
```

## Cambios necesarios en la lógica de negocio

### Emisión Flash (automática)
```
Factura aprobada → INSERT INTO cupones (comercio_id, cliente_id, codigo_qr, tipo, descuento, expira_en)
  VALUES (factura.comercio_id, factura.cliente_id, uuid(), 'flash', 10, datetime('now', '+30 days'))
```

### Emisión Hunt (manual del organizador)
```
Organizador selecciona ganador de consolación → INSERT INTO cupones (comercio_id, cliente_id, codigo_qr, tipo, descuento, expira_en, emitido_por)
  VALUES (comercio_asociado, ganador.usuario_id, uuid(), 'hunt', 15, fecha_fin_evento + 7 días, organizador.id)
```

### Canje
```
POST /cupones/canjear { codigo_qr }
  → Verifica: estado = 'activo' AND expira_en > now()
  → UPDATE estado = 'utilizado', canjeado_en = now()
  → Retorna: descuento aplicado, comercio
```

---

## Resumen de respuestas

| Pregunta | Respuesta |
|----------|-----------|
| ¿Pertenecen a Flash? | Sí, tipo `flash` |
| ¿Pertenecen a Hunt? | Sí, tipo `hunt` |
| ¿Sirven para ambos? | Sí, tabla única con campo `tipo` |
| ¿Quién los emite? | Flash: sistema automático. Hunt: organizador |
| ¿Quién los visualiza? | Cliente (sus cupones), negocio (los de su comercio), organizador (los que emitió) |
| ¿Cómo expiran? | Flash: +30 días. Hunt: fecha fin evento + 7 días |
| ¿Canje sin app del comercio? | Validación visual del QR + reporte manual |
| ¿Cómo se evita reutilización? | QR único, estado `utilizado`, validación server-side |
| ¿QR mostrado por cliente? | Sí, en pantalla "Mis cupones" |
