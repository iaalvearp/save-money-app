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

discover.get("/comercios", async (c) => {
  const db = c.env.DB;
  const categoria = c.req.query("categoria");

  let result;
  if (categoria) {
    result = await db
      .prepare(
        `SELECT c.id, c.nombre, c.categoria, c.ruc, c.latitud, c.longitud,
                c.es_patrocinado, c.horario, c.foto_url, c.created_at,
                u.nombre_completo AS propietario
         FROM comercios c
         JOIN usuarios u ON c.usuario_id = u.id
         WHERE c.categoria = ?`
      )
      .bind(categoria)
      .all();
  } else {
    result = await db
      .prepare(
        `SELECT c.id, c.nombre, c.categoria, c.ruc, c.latitud, c.longitud,
                c.es_patrocinado, c.horario, c.foto_url, c.created_at,
                u.nombre_completo AS propietario
         FROM comercios c
         JOIN usuarios u ON c.usuario_id = u.id`
      )
      .all();
  }

  return c.json({ comercios: result.results });
});

discover.get("/comercios/:id", async (c) => {
  const db = c.env.DB;
  const id = c.req.param("id");

  const comercio = await db
    .prepare(
      `SELECT c.id, c.nombre, c.categoria, c.ruc, c.latitud, c.longitud,
              c.es_patrocinado, c.horario, c.foto_url, c.created_at,
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

  return c.json({ comercio });
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
      return c.json({ error: "No tienes permiso para editar este comercio" }, 403);
    }

    const body = await c.req.json<{
      nombre?: string;
      categoria?: string;
      latitud?: number;
      longitud?: number;
      horario?: string;
      foto_url?: string;
    }>();

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
    if (body.foto_url !== undefined) {
      fields.push("foto_url = ?");
      values.push(body.foto_url);
    }

    if (fields.length === 0) {
      return c.json({ error: "No se proporcionaron campos para actualizar" }, 400);
    }

    values.push(id);
    await db
      .prepare(`UPDATE comercios SET ${fields.join(", ")} WHERE id = ?`)
      .bind(...values)
      .run();

    const updated = await db
      .prepare(
        `SELECT c.id, c.nombre, c.categoria, c.ruc, c.latitud, c.longitud,
                c.es_patrocinado, c.horario, c.foto_url, c.created_at
         FROM comercios c WHERE c.id = ?`
      )
      .bind(id)
      .first();

    return c.json({ comercio: updated });
  }
);

export { discover };
