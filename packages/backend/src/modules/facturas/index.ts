import { Hono } from "hono";
import { authMiddleware, requireRole } from "../auth/middleware";
import { validarChecksum, consultarSRI } from "../sri/index";

interface AppEnv {
  Bindings: {
    DB: D1Database;
    JWT_SECRET: string;
    SRI_ENFORCE_VALIDATION: string;
  };
  Variables: {
    user: { sub: number; rol: string };
  };
}

const facturas = new Hono<AppEnv>();

facturas.post(
  "/registrar",
  authMiddleware,
  requireRole("cliente"),
  async (c) => {
    const db = c.env.DB;
    const user = c.get("user");

    const body = await c.req.json<{
      nivel_verificacion: number;
      comercio_id?: number;
      evento_id?: number;
      clave_acceso_49?: string;
      numero_factura?: string;
      ruc_emisor?: string;
      nombre_comprador_factura?: string;
      fecha_factura?: string;
      monto_total?: number;
    }>();

    if (![1, 2, 3].includes(body.nivel_verificacion)) {
      return c.json({ error: "nivel_verificacion debe ser 1, 2 o 3" }, 400);
    }

    if (!body.comercio_id && !body.evento_id) {
      return c.json({ error: "Se requiere comercio_id o evento_id" }, 400);
    }

    if (body.nivel_verificacion === 1) {
      if (!body.clave_acceso_49) {
        return c.json(
          { error: "Nivel 1 requiere clave_acceso_49" },
          400
        );
      }

      const enforce = c.env.SRI_ENFORCE_VALIDATION === "true";

      if (enforce && !validarChecksum(body.clave_acceso_49)) {
        return c.json(
          { error: "La clave de acceso tiene un dígito verificador inválido" },
          400
        );
      }

      const sriResult = await consultarSRI(body.clave_acceso_49);

      if (
        enforce &&
        (sriResult.estado === "rechazada" ||
          sriResult.estado === "no_autorizado")
      ) {
        return c.json(
          {
            error: `Factura ${sriResult.estado} por el SRI`,
            detalle: sriResult.mensaje_sri,
          },
          422
        );
      }

      let estado: string;
      if (!enforce) {
        estado = "aprobada";
      } else if (sriResult.estado === "servicio_no_disponible") {
        estado = "pendiente_verificacion_sri";
      } else {
        const nombreUsuario = await db
          .prepare("SELECT nombre_completo FROM usuarios WHERE id = ?")
          .bind(user.sub)
          .first<{ nombre_completo: string }>();

        const nombreFactura = sriResult.nombre_comprador;
        const nombreReal = nombreUsuario?.nombre_completo;

        if (
          nombreFactura &&
          nombreReal &&
          nombreFactura.toUpperCase() !== nombreReal.toUpperCase()
        ) {
          estado = "pendiente_revision_nombre";
        } else {
          estado = "aprobada";
        }
      }

      try {
        const result = await db
          .prepare(
            `INSERT INTO facturas
              (cliente_id, comercio_id, evento_id, nivel_verificacion,
               clave_acceso_49, ruc_emisor, nombre_comprador_factura,
               fecha_factura, monto_total, estado, sri_estado_bruto)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
          )
          .bind(
            user.sub,
            body.comercio_id || null,
            body.evento_id || null,
            body.nivel_verificacion,
            body.clave_acceso_49,
            sriResult.ruc_emisor,
            sriResult.nombre_comprador,
            sriResult.fecha_autorizacion,
            sriResult.monto,
            estado,
            sriResult.estado
          )
          .run();

        return c.json(
          {
            factura_id: result.meta.last_row_id,
            estado,
            sri_estado: sriResult.estado,
          },
          201
        );
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        if (msg.includes("UNIQUE constraint failed")) {
          return c.json(
            { error: "Esta clave de acceso ya fue registrada" },
            409
          );
        }
        throw err;
      }
    }

    const result = await db
      .prepare(
        `INSERT INTO facturas
          (cliente_id, comercio_id, evento_id, nivel_verificacion,
           numero_factura, ruc_emisor, nombre_comprador_factura,
           fecha_factura, monto_total, estado)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
      )
      .bind(
        user.sub,
        body.comercio_id || null,
        body.evento_id || null,
        body.nivel_verificacion,
        body.numero_factura || null,
        body.ruc_emisor || null,
        body.nombre_comprador_factura || null,
        body.fecha_factura || null,
        body.monto_total || null,
        "aprobada"
      )
      .run();

    return c.json({ factura_id: result.meta.last_row_id, estado: "aprobada" }, 201);
  }
);

facturas.get(
  "/mias",
  authMiddleware,
  requireRole("cliente"),
  async (c) => {
    const db = c.env.DB;
    const user = c.get("user");

    const result = await db
      .prepare(
        `SELECT id, nivel_verificacion, numero_factura, ruc_emisor,
                nombre_comprador_factura, fecha_factura, monto_total,
                descuento_aplicado, estado, created_at
         FROM facturas
         WHERE cliente_id = ?
         ORDER BY created_at DESC`
      )
      .bind(user.sub)
      .all();

    return c.json({ facturas: result.results });
  }
);

export { facturas };
