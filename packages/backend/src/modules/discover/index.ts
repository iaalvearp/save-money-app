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

const discover = new Hono<AppEnv>();

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

const COMERCIOS_SELECT = `
  SELECT c.id, c.nombre, c.categoria, c.ruc, c.latitud, c.longitud,
         c.es_patrocinado, c.horario, c.hora_apertura, c.hora_cierre,
         c.foto_url, c.created_at,
         u.nombre_completo AS propietario
  FROM comercios c
  JOIN usuarios u ON c.usuario_id = u.id
`;

discover.get("/comercios", async (c) => {
  const db = c.env.DB;
  const q = c.req.query("q");
  const categoria = c.req.query("categoria");
  const conPromociones = c.req.query("con_promociones");
  const lat = c.req.query("lat");
  const lng = c.req.query("lng");

  let sql = COMERCIOS_SELECT;
  const conditions: string[] = [];
  const bindings: unknown[] = [];

  if (q) {
    conditions.push("(c.nombre LIKE ? OR c.categoria LIKE ?)");
    const pattern = `%${q}%`;
    bindings.push(pattern, pattern);
  }

  if (categoria) {
    conditions.push("c.categoria = ?");
    bindings.push(categoria);
  }

  if (conPromociones === "true") {
    conditions.push(
      `c.id IN (
        SELECT comercio_id FROM cupones
        WHERE estado = 'activo'
        AND (expira_en IS NULL OR expira_en > datetime('now'))
      )`
    );
  }

  if (conditions.length > 0) {
    sql += " WHERE " + conditions.join(" AND ");
  }

  sql += " ORDER BY c.es_patrocinado DESC, c.nombre ASC";

  const result = await db.prepare(sql).bind(...bindings).all();

  let comercios = result.results as Record<string, unknown>[];

  if (lat && lng) {
    const userLat = parseFloat(lat);
    const userLng = parseFloat(lng);
    if (!isNaN(userLat) && !isNaN(userLng)) {
      comercios = comercios.map((c) => {
        const cLat = c.latitud as number | null;
        const cLng = c.longitud as number | null;
        if (cLat != null && cLng != null) {
          const dist = haversineDistance(userLat, userLng, cLat, cLng);
          return { ...c, distancia_km: Math.round(dist * 10) / 10 };
        }
        return { ...c, distancia_km: null };
      });
    }
  }

  return c.json({ comercios });
});

discover.get("/comercios/cercanos", async (c) => {
  const db = c.env.DB;
  const lat = c.req.query("lat");
  const lng = c.req.query("lng");
  const radio = c.req.query("radio") || "5";

  if (!lat || !lng) {
    return c.json(
      { error: "Parámetros lat y lng son requeridos" },
      400
    );
  }

  const userLat = parseFloat(lat);
  const userLng = parseFloat(lng);
  const radioKm = parseFloat(radio);

  if (isNaN(userLat) || isNaN(userLng) || isNaN(radioKm)) {
    return c.json({ error: "Parámetros numéricos inválidos" }, 400);
  }

  const result = await db.prepare(COMERCIOS_SELECT).all();
  const comercios = (result.results as Record<string, unknown>[])
    .map((c) => {
      const cLat = c.latitud as number | null;
      const cLng = c.longitud as number | null;
      if (cLat != null && cLng != null) {
        const dist = haversineDistance(userLat, userLng, cLat, cLng);
        return { ...c, distancia_km: Math.round(dist * 10) / 10 };
      }
      return { ...c, distancia_km: null };
    })
    .filter((c) => {
      if (c.distancia_km === null) return false;
      return (c.distancia_km as number) <= radioKm;
    })
    .sort((a, b) => (a.distancia_km as number) - (b.distancia_km as number));

  return c.json({ comercios });
});

discover.get("/comercios/:id", async (c) => {
  const db = c.env.DB;
  const id = c.req.param("id");

  const comercio = await db
    .prepare(
      `SELECT c.id, c.nombre, c.categoria, c.ruc, c.latitud, c.longitud,
              c.es_patrocinado, c.horario, c.hora_apertura, c.hora_cierre,
              c.foto_url, c.created_at,
              u.nombre_completo AS propietario, u.email AS propietario_email
       FROM comercios c
       JOIN usuarios u ON c.usuario_id = u.id
       WHERE c.id = ?`
    )
    .bind(id)
    .first();

  if (!comercio) {
    return c.json({ error: "Comercio no encontrado" }, 404);
  }

  const promociones = await db
    .prepare(
      `SELECT id, codigo_qr, descuento, expira_en, estado
       FROM cupones
       WHERE comercio_id = ?
         AND estado = 'activo'
         AND (expira_en IS NULL OR expira_en > datetime('now'))
       ORDER BY expira_en ASC`
    )
    .bind(id)
    .all();

  return c.json({
    comercio,
    promociones: promociones.results,
  });
});

discover.put(
  "/comercios/:id",
  authMiddleware,
  requireRole("negocio", "admin"),
  async (c) => {
    const db = c.env.DB;
    const id = c.req.param("id");
    const user = c.get("user");

    const comercio = await db
      .prepare("SELECT id, usuario_id FROM comercios WHERE id = ?")
      .bind(id)
      .first<{ id: number; usuario_id: number }>();

    if (!comercio) {
      return c.json({ error: "Comercio no encontrado" }, 404);
    }

    if (user.rol !== "admin" && comercio.usuario_id !== user.sub) {
      return c.json(
        { error: "No tienes permiso para editar este comercio" },
        403
      );
    }

    const body = await c.req.json<{
      nombre?: string;
      categoria?: string;
      ruc?: string;
      latitud?: number;
      longitud?: number;
      horario?: string;
      hora_apertura?: string;
      hora_cierre?: string;
      foto_url?: string;
    }>();

    if (body.hora_apertura !== undefined && body.hora_apertura !== null) {
      if (!/^\d{2}:\d{2}$/.test(body.hora_apertura)) {
        return c.json({ error: "hora_apertura debe tener formato HH:MM" }, 400);
      }
    }
    if (body.hora_cierre !== undefined && body.hora_cierre !== null) {
      if (!/^\d{2}:\d{2}$/.test(body.hora_cierre)) {
        return c.json({ error: "hora_cierre debe tener formato HH:MM" }, 400);
      }
    }

    const fields: string[] = [];
    const values: unknown[] = [];

    if (body.nombre !== undefined) {
      fields.push("nombre = ?");
      values.push(body.nombre);
    }
    if (body.categoria !== undefined) {
      fields.push("categoria = ?");
      values.push(body.categoria);
    }
    if (body.ruc !== undefined) {
      fields.push("ruc = ?");
      values.push(body.ruc);
    }
    if (body.latitud !== undefined) {
      fields.push("latitud = ?");
      values.push(body.latitud);
    }
    if (body.longitud !== undefined) {
      fields.push("longitud = ?");
      values.push(body.longitud);
    }
    if (body.horario !== undefined) {
      fields.push("horario = ?");
      values.push(body.horario);
    }
    if (body.hora_apertura !== undefined) {
      fields.push("hora_apertura = ?");
      values.push(body.hora_apertura);
    }
    if (body.hora_cierre !== undefined) {
      fields.push("hora_cierre = ?");
      values.push(body.hora_cierre);
    }
    if (body.foto_url !== undefined) {
      fields.push("foto_url = ?");
      values.push(body.foto_url);
    }

    if (fields.length === 0) {
      return c.json(
        { error: "No se proporcionaron campos para actualizar" },
        400
      );
    }

    values.push(id);
    await db
      .prepare(`UPDATE comercios SET ${fields.join(", ")} WHERE id = ?`)
      .bind(...values)
      .run();

    const updated = await db
      .prepare(
        `SELECT c.id, c.nombre, c.categoria, c.ruc, c.latitud, c.longitud,
                c.es_patrocinado, c.horario, c.hora_apertura, c.hora_cierre,
                c.foto_url, c.created_at
         FROM comercios c WHERE c.id = ?`
      )
      .bind(id)
      .first();

    return c.json({ comercio: updated });
  }
);

discover.post(
  "/comercios",
  authMiddleware,
  requireRole("negocio", "admin"),
  async (c) => {
    const db = c.env.DB;
    const user = c.get("user");

    const body = await c.req.json<{
      nombre: string;
      categoria?: string;
      ruc?: string;
      latitud?: number;
      longitud?: number;
      horario?: string;
      hora_apertura?: string;
      hora_cierre?: string;
      foto_url?: string;
    }>();

    if (!body.nombre || body.nombre.trim().length === 0) {
      return c.json({ error: "Nombre del comercio es requerido" }, 400);
    }

    if (body.hora_apertura !== undefined && body.hora_apertura !== null) {
      if (!/^\d{2}:\d{2}$/.test(body.hora_apertura)) {
        return c.json({ error: "hora_apertura debe tener formato HH:MM" }, 400);
      }
    }
    if (body.hora_cierre !== undefined && body.hora_cierre !== null) {
      if (!/^\d{2}:\d{2}$/.test(body.hora_cierre)) {
        return c.json({ error: "hora_cierre debe tener formato HH:MM" }, 400);
      }
    }

    const result = await db
      .prepare(
        `INSERT INTO comercios (usuario_id, nombre, categoria, ruc, latitud, longitud, horario, hora_apertura, hora_cierre, foto_url)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
      )
      .bind(
        user.sub,
        body.nombre.trim(),
        body.categoria || null,
        body.ruc || null,
        body.latitud ?? null,
        body.longitud ?? null,
        body.horario || null,
        body.hora_apertura || null,
        body.hora_cierre || null,
        body.foto_url || null
      )
      .run();

    const comercioId = result.meta.last_row_id;

    const created = await db
      .prepare(
        `SELECT c.id, c.nombre, c.categoria, c.ruc, c.latitud, c.longitud,
                c.es_patrocinado, c.horario, c.hora_apertura, c.hora_cierre,
                c.foto_url, c.created_at
         FROM comercios c WHERE c.id = ?`
      )
      .bind(comercioId)
      .first();

    return c.json({ comercio: created }, 201);
  }
);

discover.get(
  "/mis-comercios",
  authMiddleware,
  requireRole("negocio"),
  async (c) => {
    const db = c.env.DB;
    const user = c.get("user");

    const result = await db
      .prepare(
        `SELECT c.id, c.nombre, c.categoria, c.ruc, c.latitud, c.longitud,
                c.es_patrocinado, c.horario, c.hora_apertura, c.hora_cierre,
                c.foto_url, c.created_at
         FROM comercios c
         WHERE c.usuario_id = ?
         ORDER BY c.nombre ASC`
      )
      .bind(user.sub)
      .all();

    return c.json({ comercios: result.results });
  }
);

export { discover };
