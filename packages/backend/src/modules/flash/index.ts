import { Hono } from "hono";
import { authMiddleware, requireRole } from "../auth/middleware";

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

function generateQrCode(): string {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  let result = "FLASH-";
  for (let i = 0; i < 12; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
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

    const cuponCode = generateQrCode();
    const expiraEn = new Date(
      new Date(promo.termina_en).getTime() + 30 * 24 * 60 * 60 * 1000
    )
      .toISOString()
      .replace("T", " ")
      .slice(0, 19);

    const cuponResult = await db
      .prepare(
        `INSERT INTO cupones
         (comercio_id, cliente_id, codigo_qr, estado, tipo, descuento, expira_en, emitido_por)
         VALUES (?, ?, ?, 'activo', 'flash', ?, ?, ?)`
      )
      .bind(
        promo.comercio_id,
        user.sub,
        cuponCode,
        promo.descuento_porcentaje,
        expiraEn,
        user.sub
      )
      .run();

    const cuponId = cuponResult.meta.last_row_id;

    await db
      .prepare(
        `INSERT INTO promociones_flash_claims
         (promocion_id, usuario_id, cupon_id)
         VALUES (?, ?, ?)`
      )
      .bind(promoId, user.sub, cuponId)
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
        id: cuponId,
        codigo_qr: cuponCode,
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

    await db
      .prepare(
        `UPDATE cupones SET estado = 'expirado'
         WHERE cliente_id = ? AND estado = 'activo'
         AND expira_en IS NOT NULL AND expira_en < datetime('now')`
      )
      .bind(user.sub)
      .run();

    const result = await db
      .prepare(
        `SELECT cu.id, cu.codigo_qr, cu.descuento, cu.estado, cu.tipo,
                cu.expira_en, cu.canjeado_en, cu.created_at,
                c.nombre AS comercio_nombre, c.foto_url AS comercio_foto
         FROM cupones cu
         JOIN comercios c ON cu.comercio_id = c.id
         WHERE cu.cliente_id = ?
         ORDER BY cu.created_at DESC`
      )
      .bind(user.sub)
      .all();

    return c.json({ cupones: result.results });
  }
);

flash.post(
  "/cupones/:id/canjear",
  authMiddleware,
  requireRole("negocio", "admin"),
  async (c) => {
    const db = c.env.DB;
    const user = c.get("user");
    const cuponId = c.req.param("id");

    const cupon = await db
      .prepare(
        `SELECT cu.*, c.usuario_id AS comercio_owner
         FROM cupones cu
         JOIN comercios c ON cu.comercio_id = c.id
         WHERE cu.id = ?`
      )
      .bind(cuponId)
      .first<{
        id: number;
        estado: string;
        expira_en: string | null;
        comercio_owner: number;
      }>();

    if (!cupon) {
      return c.json({ error: "Cupón no encontrado" }, 404);
    }

    if (user.rol !== "admin" && cupon.comercio_owner !== user.sub) {
      return c.json(
        { error: "No tienes permiso para canjear este cupón" },
        403
      );
    }

    if (cupon.estado !== "activo") {
      return c.json(
        { error: `Cupón ya fue ${cupon.estado}` },
        422
      );
    }

    if (cupon.expira_en && new Date(cupon.expira_en) < new Date()) {
      await db
        .prepare("UPDATE cupones SET estado = 'expirado' WHERE id = ?")
        .bind(cuponId)
        .run();
      return c.json({ error: "Cupón expirado" }, 422);
    }

    const now = new Date().toISOString().replace("T", " ").slice(0, 19);
    await db
      .prepare(
        `UPDATE cupones SET estado = 'utilizado', canjeado_en = ? WHERE id = ?`
      )
      .bind(now, cuponId)
      .run();

    return c.json({ mensaje: "Cupón canjeado exitosamente" });
  }
);

export { flash };
