import { Hono } from "hono";
import { authMiddleware, requireRole } from "../auth/middleware";
import { emitirCupon } from "../cupones/index";

interface AppEnv {
  Bindings: {
    DB: D1Database;
    JWT_SECRET: string;
  };
  Variables: {
    user: { sub: number; rol: string };
  };
}

const hunt = new Hono<AppEnv>();

hunt.get(
  "/eventos",
  authMiddleware,
  async (c) => {
    const db = c.env.DB;

    const result = await db
      .prepare(
        `SELECT e.*, u.nombre_completo AS organizador_nombre,
                (SELECT COUNT(*) FROM entradas ent
                 WHERE ent.evento_id = e.id AND ent.estado = 'aprobada')
                 AS entradas_vendidas
         FROM eventos e
         JOIN usuarios u ON e.organizador_id = u.id
         ORDER BY e.fecha_inicio DESC`
      )
      .all();

    return c.json({ eventos: result.results });
  }
);

hunt.get(
  "/eventos/:id",
  authMiddleware,
  async (c) => {
    const db = c.env.DB;
    const id = c.req.param("id");

    const evento = await db
      .prepare(
        `SELECT e.*, u.nombre_completo AS organizador_nombre
         FROM eventos e
         JOIN usuarios u ON e.organizador_id = u.id
         WHERE e.id = ?`
      )
      .bind(id)
      .first();

    if (!evento) {
      return c.json({ error: "Evento no encontrado" }, 404);
    }

    const rondas = await db
      .prepare(
        `SELECT * FROM rondas WHERE evento_id = ? ORDER BY hora_inicio ASC`
      )
      .bind(id)
      .all();

    const premios = await db
      .prepare(
        `SELECT p.*,
                (SELECT COUNT(*) FROM premios_entregados pe
                 WHERE pe.premio_id = p.id AND pe.estado = 'entregado')
                 AS entregados
         FROM premios p WHERE p.evento_id = ?`
      )
      .bind(id)
      .all();

    const sponsors = await db
      .prepare(
        `SELECT es.*, c.nombre AS comercio_nombre, c.categoria
         FROM eventos_sponsors es
         JOIN comercios c ON es.comercio_id = c.id
         WHERE es.evento_id = ?`
      )
      .bind(id)
      .all();

    return c.json({ evento, rondas: rondas.results, premios: premios.results, sponsors: sponsors.results });
  }
);

hunt.post(
  "/eventos",
  authMiddleware,
  requireRole("organizador", "admin"),
  async (c) => {
    const db = c.env.DB;
    const user = c.get("user");

    const body = await c.req.json<{
      nombre: string;
      fecha_inicio: string;
      fecha_fin: string;
      requiere_entrada?: boolean;
      precio_entrada?: number;
    }>();

    if (!body.nombre || body.nombre.trim().length === 0) {
      return c.json({ error: "Nombre del evento es requerido" }, 400);
    }
    if (!body.fecha_inicio || !body.fecha_fin) {
      return c.json({ error: "Fechas de inicio y fin son requeridas" }, 400);
    }
    if (new Date(body.fecha_fin) <= new Date(body.fecha_inicio)) {
      return c.json({ error: "La fecha de fin debe ser posterior al inicio" }, 400);
    }

    const result = await db
      .prepare(
        `INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin, requiere_entrada, precio_entrada)
         VALUES (?, ?, ?, ?, ?, ?)`
      )
      .bind(
        user.sub,
        body.nombre.trim(),
        body.fecha_inicio,
        body.fecha_fin,
        body.requiere_entrada ? 1 : 0,
        body.precio_entrada ?? null
      )
      .run();

    const eventoId = result.meta.last_row_id;
    const created = await db
      .prepare("SELECT * FROM eventos WHERE id = ?")
      .bind(eventoId)
      .first();

    return c.json({ evento: created }, 201);
  }
);

hunt.post(
  "/eventos/:id/rondas",
  authMiddleware,
  requireRole("organizador", "admin"),
  async (c) => {
    const db = c.env.DB;
    const user = c.get("user");
    const eventoId = c.req.param("id");

    const evento = await db
      .prepare("SELECT id, organizador_id, fecha_inicio, fecha_fin FROM eventos WHERE id = ?")
      .bind(eventoId)
      .first<{ id: number; organizador_id: number; fecha_inicio: string; fecha_fin: string }>();

    if (!evento) {
      return c.json({ error: "Evento no encontrado" }, 404);
    }
    if (user.rol !== "admin" && evento.organizador_id !== user.sub) {
      return c.json({ error: "No tienes permiso" }, 403);
    }

    const body = await c.req.json<{
      nombre: string;
      hora_inicio: string;
      hora_fin: string;
    }>();

    if (!body.nombre || !body.hora_inicio || !body.hora_fin) {
      return c.json({ error: "Nombre, hora_inicio y hora_fin son requeridos" }, 400);
    }

    const result = await db
      .prepare(
        `INSERT INTO rondas (evento_id, nombre, hora_inicio, hora_fin)
         VALUES (?, ?, ?, ?)`
      )
      .bind(eventoId, body.nombre.trim(), body.hora_inicio, body.hora_fin)
      .run();

    const rondaId = result.meta.last_row_id;
    const created = await db.prepare("SELECT * FROM rondas WHERE id = ?").bind(rondaId).first();

    return c.json({ ronda: created }, 201);
  }
);

hunt.post(
  "/eventos/:id/sponsors",
  authMiddleware,
  requireRole("organizador", "admin"),
  async (c) => {
    const db = c.env.DB;
    const user = c.get("user");
    const eventoId = c.req.param("id");

    const evento = await db
      .prepare("SELECT id, organizador_id FROM eventos WHERE id = ?")
      .bind(eventoId)
      .first<{ id: number; organizador_id: number }>();

    if (!evento) {
      return c.json({ error: "Evento no encontrado" }, 404);
    }
    if (user.rol !== "admin" && evento.organizador_id !== user.sub) {
      return c.json({ error: "No tienes permiso" }, 403);
    }

    const body = await c.req.json<{ comercio_id: number }>();

    const comercio = await db
      .prepare("SELECT id FROM comercios WHERE id = ?")
      .bind(body.comercio_id)
      .first();

    if (!comercio) {
      return c.json({ error: "Comercio no encontrado" }, 404);
    }

    const existing = await db
      .prepare(
        "SELECT id FROM eventos_sponsors WHERE evento_id = ? AND comercio_id = ?"
      )
      .bind(eventoId, body.comercio_id)
      .first();

    if (existing) {
      return c.json({ error: "Ya existe una invitación para este comercio" }, 409);
    }

    await db
      .prepare(
        `INSERT INTO eventos_sponsors (evento_id, comercio_id)
         VALUES (?, ?)`
      )
      .bind(eventoId, body.comercio_id)
      .run();

    return c.json({ mensaje: "Invitación enviada" }, 201);
  }
);

hunt.post(
  "/eventos/:eventoId/sponsors/:sponsorId/responder",
  authMiddleware,
  requireRole("negocio"),
  async (c) => {
    const db = c.env.DB;
    const user = c.get("user");
    const eventoId = c.req.param("eventoId");
    const sponsorId = c.req.param("sponsorId");

    const sponsor = await db
      .prepare(
        `SELECT es.*, c.usuario_id
         FROM eventos_sponsors es
         JOIN comercios c ON es.comercio_id = c.id
         WHERE es.id = ? AND es.evento_id = ?`
      )
      .bind(sponsorId, eventoId)
      .first<{ id: number; usuario_id: number; estado: string }>();

    if (!sponsor) {
      return c.json({ error: "Invitación no encontrada" }, 404);
    }

    if (sponsor.usuario_id !== user.sub) {
      return c.json({ error: "No tienes permiso" }, 403);
    }

    if (sponsor.estado !== "pendiente") {
      return c.json({ error: "Ya respondiste esta invitación" }, 422);
    }

    const body = await c.req.json<{ acepta: boolean }>();

    await db
      .prepare(
        `UPDATE eventos_sponsors
         SET estado = ?, responded_at = datetime('now')
         WHERE id = ?`
      )
      .bind(body.acepta ? "aprobado" : "rechazado", sponsorId)
      .run();

    return c.json({
      mensaje: body.acepta ? "Patrocinio aceptado" : "Patrocinio rechazado",
    });
  }
);

hunt.post(
  "/eventos/:id/premios",
  authMiddleware,
  requireRole("organizador", "admin"),
  async (c) => {
    const db = c.env.DB;
    const user = c.get("user");
    const eventoId = c.req.param("id");

    const evento = await db
      .prepare("SELECT id, organizador_id FROM eventos WHERE id = ?")
      .bind(eventoId)
      .first<{ id: number; organizador_id: number }>();

    if (!evento) {
      return c.json({ error: "Evento no encontrado" }, 404);
    }
    if (user.rol !== "admin" && evento.organizador_id !== user.sub) {
      return c.json({ error: "No tienes permiso" }, 403);
    }

    const body = await c.req.json<{
      nombre: string;
      stock: number;
      tipo: string;
      ronda_id?: number;
      criterio_frecuencia?: number;
    }>();

    if (!body.nombre || body.stock <= 0) {
      return c.json({ error: "Nombre y stock válido son requeridos" }, 400);
    }

    if (!["principal", "consolacion", "frecuencia"].includes(body.tipo)) {
      return c.json({ error: "Tipo inválido. Debe ser: principal, consolacion, frecuencia" }, 400);
    }

    const result = await db
      .prepare(
        `INSERT INTO premios (evento_id, ronda_id, nombre, stock, tipo, criterio_frecuencia)
         VALUES (?, ?, ?, ?, ?, ?)`
      )
      .bind(
        eventoId,
        body.ronda_id ?? null,
        body.nombre.trim(),
        body.stock,
        body.tipo,
        body.criterio_frecuencia ?? null
      )
      .run();

    const premioId = result.meta.last_row_id;
    const created = await db.prepare("SELECT * FROM premios WHERE id = ?").bind(premioId).first();

    return c.json({ premio: created }, 201);
  }
);

hunt.post(
  "/eventos/:eventoId/premios/:premioId/entregar",
  authMiddleware,
  requireRole("organizador", "admin"),
  async (c) => {
    const db = c.env.DB;
    const user = c.get("user");
    const eventoId = c.req.param("eventoId");
    const premioId = c.req.param("premioId");

    const premio = await db
      .prepare(
        `SELECT p.*, (SELECT COUNT(*) FROM premios_entregados pe
         WHERE pe.premio_id = p.id AND pe.estado = 'entregado') AS entregados
         FROM premios p WHERE p.id = ? AND p.evento_id = ?`
      )
      .bind(premioId, eventoId)
      .first<{ id: number; stock: number; entregados: number }>();

    if (!premio) {
      return c.json({ error: "Premio no encontrado" }, 404);
    }

    if (premio.entregados >= premio.stock) {
      return c.json({ error: "Premio sin stock disponible" }, 422);
    }

    const body = await c.req.json<{ usuario_id: number; ronda_id?: number }>();

    const yaEntregado = await db
      .prepare(
        `SELECT id FROM premios_entregados
         WHERE premio_id = ? AND usuario_id = ? AND ronda_id IS ? AND estado = 'entregado'`
      )
      .bind(premioId, body.usuario_id, body.ronda_id ?? null)
      .first();

    if (yaEntregado) {
      return c.json({ error: "Ya se entregó este premio a este usuario" }, 409);
    }

    await db
      .prepare(
        `INSERT INTO premios_entregados (premio_id, usuario_id, ronda_id)
         VALUES (?, ?, ?)`
      )
      .bind(premioId, body.usuario_id, body.ronda_id ?? null)
      .run();

    return c.json({ mensaje: "Premio entregado" }, 201);
  }
);

hunt.post(
  "/eventos/:eventoId/premios/:premioId/reclamar",
  authMiddleware,
  async (c) => {
    const db = c.env.DB;
    const user = c.get("user");
    const eventoId = c.req.param("eventoId");
    const premioId = c.req.param("premioId");
    const now = new Date().toISOString().replace("T", " ").slice(0, 19);

    const evento = await db
      .prepare("SELECT id, fecha_inicio, fecha_fin, requiere_entrada FROM eventos WHERE id = ?")
      .bind(eventoId)
      .first<{ id: number; fecha_inicio: string; fecha_fin: string; requiere_entrada: number }>();

    if (!evento) {
      return c.json({ error: "Evento no encontrado" }, 404);
    }

    const nowDate = new Date(now);
    if (nowDate < new Date(evento.fecha_inicio) || nowDate > new Date(evento.fecha_fin)) {
      return c.json({ error: "Fuera del horario del evento" }, 422);
    }

    if (evento.requiere_entrada) {
      const entrada = await db
        .prepare(
          `SELECT id FROM entradas
           WHERE evento_id = ? AND cliente_id = ? AND estado = 'aprobada'`
        )
        .bind(eventoId, user.sub)
        .first();

      if (!entrada) {
        return c.json({ error: "Se requiere una entrada aprobada para reclamar premios" }, 403);
      }
    }

    const premio = await db
      .prepare("SELECT id, ronda_id, stock, nombre FROM premios WHERE id = ? AND evento_id = ?")
      .bind(premioId, eventoId)
      .first<{ id: number; ronda_id: number | null; stock: number; nombre: string }>();

    if (!premio) {
      return c.json({ error: "Premio no encontrado" }, 404);
    }

    const yaReclamado = await db
      .prepare(
        `SELECT id FROM premios_entregados
         WHERE usuario_id = ? AND ronda_id IS ? AND estado = 'entregado'`
      )
      .bind(user.sub, premio.ronda_id ?? null)
      .first();

    if (yaReclamado) {
      return c.json({ error: "Ya reclamaste un premio en esta ronda" }, 409);
    }

    const stockRow = await db
      .prepare(
        `SELECT COUNT(*) AS cnt FROM premios_entregados
         WHERE premio_id = ? AND estado = 'entregado'`
      )
      .bind(premioId)
      .first<{ cnt: number }>();

    if (stockRow && stockRow.cnt >= premio.stock) {
      return c.json({ error: "Premio sin stock disponible" }, 422);
    }

    try {
      await db
        .prepare(
          `INSERT INTO premios_entregados (premio_id, usuario_id, ronda_id, estado, entregado_en, reclamado_en)
           VALUES (?, ?, ?, 'entregado', ?, ?)`
        )
        .bind(premioId, user.sub, premio.ronda_id ?? null, now, now)
        .run();
    } catch (e: any) {
      if (e?.message?.includes("UNIQUE constraint")) {
        return c.json({ error: "Ya reclamaste un premio en esta ronda" }, 409);
      }
      throw e;
    }

    await db
      .prepare(
        `INSERT INTO puntos_evento (evento_id, usuario_id, puntos)
         VALUES (?, ?, 10)
         ON CONFLICT (evento_id, usuario_id)
         DO UPDATE SET puntos = puntos + 10`
      )
      .bind(eventoId, user.sub)
      .run();

    return c.json({
      mensaje: `Premio "${premio.nombre}" reclamado`,
      premio_id: premioId,
      puntos_ganados: 10,
    }, 201);
  }
);

hunt.post(
  "/eventos/:eventoId/entradas/comprar",
  authMiddleware,
  async (c) => {
    const db = c.env.DB;
    const user = c.get("user");
    const eventoId = c.req.param("eventoId");

    const evento = await db
      .prepare("SELECT id, requiere_entrada, precio_entrada FROM eventos WHERE id = ?")
      .bind(eventoId)
      .first<{ id: number; requiere_entrada: number; precio_entrada: number | null }>();

    if (!evento) {
      return c.json({ error: "Evento no encontrado" }, 404);
    }

    if (!evento.requiere_entrada) {
      return c.json({ error: "Este evento no requiere entrada" }, 422);
    }

    const existing = await db
      .prepare(
        `SELECT id, estado FROM entradas
         WHERE evento_id = ? AND cliente_id = ?
         AND estado IN ('pendiente_pago', 'pendiente_revision_comprobante', 'aprobada')`
      )
      .bind(eventoId, user.sub)
      .first<{ id: number; estado: string }>();

    if (existing) {
      return c.json(
        { error: `Ya tienes una entrada con estado: ${existing.estado}` },
        409
      );
    }

    const result = await db
      .prepare(
        `INSERT INTO entradas (evento_id, cliente_id, estado, monto)
         VALUES (?, ?, 'pendiente_pago', ?)`
      )
      .bind(eventoId, user.sub, evento.precio_entrada)
      .run();

    const entradaId = result.meta.last_row_id;
    const created = await db
      .prepare("SELECT * FROM entradas WHERE id = ?")
      .bind(entradaId)
      .first();

    return c.json({ entrada: created }, 201);
  }
);

hunt.post(
  "/entradas/:id/comprobante",
  authMiddleware,
  async (c) => {
    const db = c.env.DB;
    const user = c.get("user");
    const entradaId = c.req.param("id");

    const entrada = await db
      .prepare("SELECT id, cliente_id, estado FROM entradas WHERE id = ?")
      .bind(entradaId)
      .first<{ id: number; cliente_id: number; estado: string }>();

    if (!entrada) {
      return c.json({ error: "Entrada no encontrada" }, 404);
    }

    if (entrada.cliente_id !== user.sub) {
      return c.json({ error: "No tienes permiso" }, 403);
    }

    if (entrada.estado !== "pendiente_pago") {
      return c.json({ error: `Entrada con estado: ${entrada.estado}` }, 422);
    }

    const body = await c.req.json<{ comprobante_foto: string }>();

    await db
      .prepare(
        `UPDATE entradas
         SET comprobante_foto = ?, estado = 'pendiente_revision_comprobante'
         WHERE id = ?`
      )
      .bind(body.comprobante_foto, entradaId)
      .run();

    return c.json({ mensaje: "Comprobante registrado" });
  }
);

hunt.post(
  "/entradas/:id/revisar",
  authMiddleware,
  requireRole("organizador", "admin"),
  async (c) => {
    const db = c.env.DB;
    const user = c.get("user");
    const entradaId = c.req.param("id");

    const entrada = await db
      .prepare(
        `SELECT ent.*, e.organizador_id
         FROM entradas ent
         JOIN eventos e ON ent.evento_id = e.id
         WHERE ent.id = ?`
      )
      .bind(entradaId)
      .first<{ id: number; organizador_id: number; estado: string }>();

    if (!entrada) {
      return c.json({ error: "Entrada no encontrada" }, 404);
    }

    if (user.rol !== "admin" && entrada.organizador_id !== user.sub) {
      return c.json({ error: "No tienes permiso" }, 403);
    }

    if (entrada.estado !== "pendiente_revision_comprobante") {
      return c.json({ error: `Entrada con estado: ${entrada.estado}` }, 422);
    }

    const body = await c.req.json<{ aprueba: boolean }>();

    const now = new Date().toISOString().replace("T", " ").slice(0, 19);

    await db
      .prepare(
        `UPDATE entradas
         SET estado = ?, revisado_por = ?, revisado_en = ?
         WHERE id = ?`
      )
      .bind(body.aprueba ? "aprobada" : "rechazada", user.sub, now, entradaId)
      .run();

    return c.json({
      mensaje: body.aprueba ? "Entrada aprobada" : "Entrada rechazada",
    });
  }
);

hunt.get(
  "/eventos/:eventoId/entradas",
  authMiddleware,
  requireRole("organizador", "admin"),
  async (c) => {
    const db = c.env.DB;
    const user = c.get("user");
    const eventoId = c.req.param("eventoId");

    const evento = await db
      .prepare("SELECT organizador_id FROM eventos WHERE id = ?")
      .bind(eventoId)
      .first<{ organizador_id: number }>();

    if (!evento) {
      return c.json({ error: "Evento no encontrado" }, 404);
    }
    if (user.rol !== "admin" && evento.organizador_id !== user.sub) {
      return c.json({ error: "No tienes permiso" }, 403);
    }

    const result = await db
      .prepare(
        `SELECT ent.*, u.nombre_completo AS cliente_nombre, u.email AS cliente_email
         FROM entradas ent
         JOIN usuarios u ON ent.cliente_id = u.id
         WHERE ent.evento_id = ?
         ORDER BY ent.created_at DESC`
      )
      .bind(eventoId)
      .all();

    return c.json({ entradas: result.results });
  }
);

hunt.post(
  "/eventos/:eventoId/cupones-consolacion",
  authMiddleware,
  requireRole("organizador", "admin"),
  async (c) => {
    const db = c.env.DB;
    const user = c.get("user");
    const eventoId = c.req.param("eventoId");

    const evento = await db
      .prepare("SELECT id, organizador_id, fecha_fin FROM eventos WHERE id = ?")
      .bind(eventoId)
      .first<{ id: number; organizador_id: number; fecha_fin: string }>();

    if (!evento) {
      return c.json({ error: "Evento no encontrado" }, 404);
    }
    if (user.rol !== "admin" && evento.organizador_id !== user.sub) {
      return c.json({ error: "No tienes permiso" }, 403);
    }

    const body = await c.req.json<{
      comercio_id: number;
      usuario_ids: number[];
      descuento: number;
    }>();

    if (!body.usuario_ids || body.usuario_ids.length === 0) {
      return c.json({ error: "Se requiere al menos un usuario" }, 400);
    }

    const comercio = await db
      .prepare("SELECT id FROM comercios WHERE id = ?")
      .bind(body.comercio_id)
      .first();

    if (!comercio) {
      return c.json({ error: "Comercio no encontrado" }, 404);
    }

    const fechaFinEvento = new Date(evento.fecha_fin);
    const expiraEn = new Date(
      fechaFinEvento.getTime() + 7 * 24 * 60 * 60 * 1000
    )
      .toISOString()
      .replace("T", " ")
      .slice(0, 19);

    const cuponesCreados: number[] = [];

    for (const userId of body.usuario_ids) {
      const cupon = await emitirCupon({
        db,
        comercioId: body.comercio_id,
        clienteId: userId,
        descuento: body.descuento,
        expiraEn,
        tipo: "hunt",
        emitidoPor: user.sub,
      });
      cuponesCreados.push(cupon.id);
    }

    return c.json({
      cupones_creados: cuponesCreados.length,
      expira_en: expiraEn,
    }, 201);
  }
);

export { hunt };
