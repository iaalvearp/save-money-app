import { Hono } from "hono";
import { authMiddleware, requireRole } from "../auth/middleware";
import {
  emitirCupon,
  listarCuponesDeUsuario,
  canjearCupon,
} from "../cupones/index";

interface AppEnv {
  Bindings: {
    DB: D1Database;
    JWT_SECRET: string;
  };
  Variables: {
    user: { sub: number; rol: string };
  };
}

const flash = new Hono<AppEnv>();

function haversineDistance(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number
): number {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

flash.get(
  "/promociones",
  authMiddleware,
  async (c) => {
    const db = c.env.DB;
    const lat = c.req.query("lat");
    const lng = c.req.query("lng");
    const categoria = c.req.query("categoria");

    const result = await db
      .prepare(
        `SELECT pf.*, c.nombre AS comercio_nombre, c.categoria AS comercio_categoria
         FROM promociones_flash pf
         JOIN comercios c ON pf.comercio_id = c.id
         WHERE pf.inicia_en <= datetime('now')
           AND pf.termina_en > datetime('now')
         ORDER BY pf.inicia_en DESC`
      )
      .all();

    let promociones = result.results as Record<string, unknown>[];

    if (categoria) {
      promociones = promociones.filter(
        (p) =>
          p.categoria === categoria ||
          p.comercio_categoria === categoria
      );
    }

    if (lat && lng) {
      const userLat = parseFloat(lat);
      const userLng = parseFloat(lng);
      if (!isNaN(userLat) && !isNaN(userLng)) {
        promociones = promociones.filter((p) => {
          const pLat = p.latitud as number | null;
          const pLng = p.longitud as number | null;
          const radio = (p.radio_km as number) || 5;
          if (pLat == null || pLng == null) return true;
          const dist = haversineDistance(userLat, userLng, pLat, pLng);
          return dist <= radio;
        });
      }
    }

    return c.json({ promociones });
  }
);

flash.get(
  "/promociones/:id",
  authMiddleware,
  async (c) => {
    const db = c.env.DB;
    const id = c.req.param("id");

    const promo = await db
      .prepare(
        `SELECT pf.*, c.nombre AS comercio_nombre, c.categoria AS comercio_categoria
         FROM promociones_flash pf
         JOIN comercios c ON pf.comercio_id = c.id
         WHERE pf.id = ?`
      )
      .bind(id)
      .first();

    if (!promo) {
      return c.json({ error: "Promoción no encontrada" }, 404);
    }

    const user = c.get("user");
    const claim = await db
      .prepare(
        `SELECT id FROM promociones_flash_claims
         WHERE promocion_id = ? AND usuario_id = ?`
      )
      .bind(id, user.sub)
      .first();

    return c.json({
      promocion: promo,
      ya_reclamada: claim != null,
    });
  }
);

flash.post(
  "/promociones",
  authMiddleware,
  requireRole("negocio", "admin"),
  async (c) => {
    const db = c.env.DB;
    const user = c.get("user");

    const body = await c.req.json<{
      comercio_id: number;
      titulo: string;
      descripcion?: string;
      descuento_porcentaje: number;
      inicia_en: string;
      termina_en: string;
      latitud?: number;
      longitud?: number;
      radio_km?: number;
      categoria?: string;
      max_usuarios?: number;
    }>();

    if (!body.titulo || body.titulo.trim().length === 0) {
      return c.json({ error: "Título es requerido" }, 400);
    }

    if (
      !body.descuento_porcentaje ||
      body.descuento_porcentaje <= 0 ||
      body.descuento_porcentaje > 100
    ) {
      return c.json(
        { error: "Descuento debe ser entre 1 y 100" },
        400
      );
    }

    if (!body.inicia_en || !body.termina_en) {
      return c.json(
        { error: "Fechas de inicio y fin son requeridas" },
        400
      );
    }

    if (new Date(body.termina_en) <= new Date(body.inicia_en)) {
      return c.json(
        { error: "La fecha de fin debe ser posterior al inicio" },
        400
      );
    }

    if (body.comercio_id) {
      const comercio = await db
        .prepare(
          "SELECT id, usuario_id FROM comercios WHERE id = ?"
        )
        .bind(body.comercio_id)
        .first<{ id: number; usuario_id: number }>();

      if (!comercio) {
        return c.json({ error: "Comercio no encontrado" }, 404);
      }

      if (user.rol !== "admin" && comercio.usuario_id !== user.sub) {
        return c.json(
          { error: "No tienes permiso para crear promociones en este comercio" },
          403
        );
      }
    }

    const result = await db
      .prepare(
        `INSERT INTO promociones_flash
         (comercio_id, titulo, descripcion, descuento_porcentaje,
          inicia_en, termina_en, latitud, longitud, radio_km,
          categoria, max_usuarios)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
      )
      .bind(
        body.comercio_id,
        body.titulo.trim(),
        body.descripcion || null,
        body.descuento_porcentaje,
        body.inicia_en,
        body.termina_en,
        body.latitud ?? null,
        body.longitud ?? null,
        body.radio_km ?? 5,
        body.categoria || null,
        body.max_usuarios ?? null
      )
      .run();

    const promoId = result.meta.last_row_id;

    const created = await db
      .prepare("SELECT * FROM promociones_flash WHERE id = ?")
      .bind(promoId)
      .first();

    return c.json({ promocion: created }, 201);
  }
);

flash.post(
  "/promociones/:id/claim",
  authMiddleware,
  async (c) => {
    const db = c.env.DB;
    const user = c.get("user");
    const promoId = c.req.param("id");

    const promo = await db
      .prepare(
        `SELECT pf.*, c.nombre AS comercio_nombre
         FROM promociones_flash pf
         JOIN comercios c ON pf.comercio_id = c.id
         WHERE pf.id = ?`
      )
      .bind(promoId)
      .first<{
        id: number;
        comercio_id: number;
        titulo: string;
        descuento_porcentaje: number;
        inicia_en: string;
        termina_en: string;
        latitud: number | null;
        longitud: number | null;
        radio_km: number;
        categoria: string | null;
        max_usuarios: number | null;
        usuarios_notificados: number;
        comercio_nombre: string;
      }>();

    if (!promo) {
      return c.json({ error: "Promoción no encontrada" }, 404);
    }

    const now = new Date();
    if (now < new Date(promo.inicia_en)) {
      return c.json({ error: "La promoción aún no ha iniciado" }, 422);
    }
    if (now > new Date(promo.termina_en)) {
      return c.json({ error: "La promoción ha expirado" }, 422);
    }

    const existingClaim = await db
      .prepare(
        `SELECT id FROM promociones_flash_claims
         WHERE promocion_id = ? AND usuario_id = ?`
      )
      .bind(promoId, user.sub)
      .first();

    if (existingClaim) {
      return c.json(
        { error: "Ya reclamaste esta promoción" },
        409
      );
    }

    if (
      promo.max_usuarios != null &&
      promo.usuarios_notificados >= promo.max_usuarios
    ) {
      return c.json(
        { error: "Esta promoción ha alcanzado el máximo de usuarios" },
        422
      );
    }

    const expiraEn = new Date(
      new Date(promo.termina_en).getTime() + 30 * 24 * 60 * 60 * 1000
    )
      .toISOString()
      .replace("T", " ")
      .slice(0, 19);

    const cupon = await emitirCupon({
      db,
      comercioId: promo.comercio_id,
      clienteId: user.sub,
      descuento: promo.descuento_porcentaje,
      expiraEn,
      tipo: "flash",
      emitidoPor: user.sub,
    });

    await db
      .prepare(
        `INSERT INTO promociones_flash_claims
         (promocion_id, usuario_id, cupon_id)
         VALUES (?, ?, ?)`
      )
      .bind(promoId, user.sub, cupon.id)
      .run();

    await db
      .prepare(
        `UPDATE promociones_flash
         SET usuarios_notificados = usuarios_notificados + 1
         WHERE id = ?`
      )
      .bind(promoId)
      .run();

    return c.json({
      cupon: {
        id: cupon.id,
        codigo_qr: cupon.codigo_qr,
        descuento: promo.descuento_porcentaje,
        comercio: promo.comercio_nombre,
        expira_en: expiraEn,
      },
      mensaje: `¡${promo.descuento_porcentaje}% de descuento en ${promo.comercio_nombre}!`,
    }, 201);
  }
);

flash.get(
  "/mis-cupones",
  authMiddleware,
  async (c) => {
    const db = c.env.DB;
    const user = c.get("user");

    const cupones = await listarCuponesDeUsuario(db, user.sub);
    return c.json({ cupones });
  }
);

flash.post(
  "/cupones/:id/canjear",
  authMiddleware,
  requireRole("negocio", "admin"),
  async (c) => {
    const db = c.env.DB;
    const user = c.get("user");
    const cuponId = Number(c.req.param("id"));

    const cupon = await db
      .prepare(
        `SELECT cu.comercio_id, c.usuario_id AS comercio_owner
         FROM cupones cu
         JOIN comercios c ON cu.comercio_id = c.id
         WHERE cu.id = ?`
      )
      .bind(cuponId)
      .first<{ comercio_id: number; comercio_owner: number }>();

    if (!cupon) {
      return c.json({ error: "Cupón no encontrado" }, 404);
    }

    if (user.rol !== "admin" && cupon.comercio_owner !== user.sub) {
      return c.json(
        { error: "No tienes permiso para canjear este cupón" },
        403
      );
    }

    const result = await canjearCupon(db, cuponId, cupon.comercio_id);

    if (!result.ok) {
      const status = result.error?.includes("no encontrado")
        ? 404
        : result.error?.includes("expirado")
          ? 422
          : 422;
      return c.json({ error: result.error }, status);
    }

    return c.json({ mensaje: "Cupón canjeado exitosamente" });
  }
);

export { flash };
