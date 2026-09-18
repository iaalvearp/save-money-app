import { Hono } from "hono";
import { authMiddleware, requireRole } from "../auth/middleware";
import {
  validarChecksum as defaultValidarChecksum,
  consultarSRI as defaultConsultarSRI,
} from "../sri/index";
import type { SRIResultado } from "../sri/index";

function generarNonce(): string {
  const array = new Uint8Array(32);
  crypto.getRandomValues(array);
  return Array.from(array, (b) => b.toString(16).padStart(2, "0")).join("");
}

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

type ValidarChecksumFn = (clave: string) => boolean;
type ConsultarSRIFn = (clave: string) => Promise<SRIResultado>;

export function createFacturas(
  validarChecksumFn: ValidarChecksumFn = defaultValidarChecksum,
  consultarSRIFn: ConsultarSRIFn = defaultConsultarSRI
) {
  const facturas = new Hono<AppEnv>();

facturas.post(
  "/challenge",
  authMiddleware,
  requireRole("cliente"),
  async (c) => {
    const db = c.env.DB;
    const user = c.get("user");

    const nonce = generarNonce();
    const expiraEn = new Date(Date.now() + 5 * 60 * 1000).toISOString();

    await db
      .prepare(
        `INSERT INTO challenges (cliente_id, nonce, expira_en)
         VALUES (?, ?, ?)`
      )
      .bind(user.sub, nonce, expiraEn)
      .run();

    return c.json({ nonce, expira_en: expiraEn }, 201);
  }
);

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
      challenge_nonce?: string;
      claim_hash?: string;
    }>();

    if (![1, 2, 3].includes(body.nivel_verificacion)) {
      return c.json({ error: "nivel_verificacion debe ser 1, 2 o 3" }, 400);
    }

    if (!body.comercio_id && !body.evento_id) {
      return c.json({ error: "Se requiere comercio_id o evento_id" }, 400);
    }

    if (body.nivel_verificacion === 3) {
      if (!body.challenge_nonce) {
        return c.json(
          { error: "Nivel 3 requiere challenge_nonce" },
          400
        );
      }

      const challenge = await db
        .prepare(
          "SELECT id, expira_en, usado FROM challenges WHERE nonce = ? AND cliente_id = ?"
        )
        .bind(body.challenge_nonce, user.sub)
        .first<{ id: number; expira_en: string; usado: number }>();

      if (!challenge) {
        return c.json(
          { error: "Desafío inválido o no encontrado" },
          400
        );
      }

      if (challenge.usado) {
        return c.json(
          { error: "Este desafío ya fue utilizado" },
          409
        );
      }

      const now = new Date();
      const expira = new Date(challenge.expira_en);
      if (now > expira) {
        return c.json(
          { error: "El desafío ha expirado. Solicite uno nuevo." },
          410
        );
      }

      await db
        .prepare("UPDATE challenges SET usado = 1 WHERE id = ?")
        .bind(challenge.id)
        .run();

      try {
        const result = await db
          .prepare(
            `INSERT INTO facturas
              (cliente_id, comercio_id, evento_id, nivel_verificacion,
               numero_factura, ruc_emisor, nombre_comprador_factura,
               fecha_factura, monto_total, estado, motivo_rechazo,
               challenge_nonce, claim_hash)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
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
            "pendiente_revision_nombre",
            "Compra declarada sin comprobante, pendiente validación",
            body.challenge_nonce,
            body.claim_hash || null
          )
          .run();

        return c.json(
          {
            factura_id: result.meta.last_row_id,
            estado: "pendiente_revision_nombre",
            motivo_rechazo: "Compra declarada sin comprobante, pendiente validación",
          },
          201
        );
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        if (msg.includes("UNIQUE constraint failed")) {
          return c.json(
            { error: "Ya existe un registro con este desafío" },
            409
          );
        }
        throw err;
      }
    }

    if (body.nivel_verificacion === 1) {
      if (!body.clave_acceso_49) {
        return c.json(
          { error: "Nivel 1 requiere clave_acceso_49" },
          400
        );
      }

      const enforce = c.env.SRI_ENFORCE_VALIDATION === "true";

      const insertRechazada = async (
        motivo: string,
        sriEstadoBruto?: string
      ) => {
        try {
          await db
            .prepare(
              `INSERT INTO facturas
                (cliente_id, comercio_id, evento_id, nivel_verificacion,
                 clave_acceso_49, estado, motivo_rechazo, sri_estado_bruto)
               VALUES (?, ?, ?, ?, ?, 'rechazada', ?, ?)`
            )
            .bind(
              user.sub,
              body.comercio_id || null,
              body.evento_id || null,
              body.nivel_verificacion,
              body.clave_acceso_49,
              motivo,
              sriEstadoBruto || null
            )
            .run();
        } catch (err) {
          const msg = err instanceof Error ? err.message : String(err);
          if (msg.includes("UNIQUE constraint failed")) {
            return c.json(
              { error: "Esta clave ya fue registrada o intentada anteriormente" },
              409
            );
          }
          throw err;
        }
        return null;
      };

      if (enforce && !validarChecksumFn(body.clave_acceso_49)) {
        const duplicate = await insertRechazada(
          "Checksum inválido en clave de acceso"
        );
        if (duplicate) return duplicate;
        return c.json(
          { error: "La clave de acceso tiene un dígito verificador inválido" },
          400
        );
      }

      const sriResult = await consultarSRIFn(body.clave_acceso_49);

      const existingPending = await db
        .prepare(
          "SELECT id, cliente_id, estado FROM facturas WHERE clave_acceso_49 = ?"
        )
        .bind(body.clave_acceso_49)
        .first<{ id: number; cliente_id: number; estado: string }>();

      if (
        existingPending &&
        existingPending.estado === "pendiente_verificacion_sri"
      ) {
        if (existingPending.cliente_id !== user.sub) {
          return c.json(
            { error: "Esta clave ya fue registrada o intentada anteriormente" },
            409
          );
        }

        if (sriResult.estado === "servicio_no_disponible") {
          return c.json(
            {
              factura_id: existingPending.id,
              estado: "pendiente_verificacion_sri",
              mensaje: "SRI sigue no disponible. Puede reintentar más tarde.",
            },
            200
          );
        }

        if (
          sriResult.estado === "rechazada" ||
          sriResult.estado === "no_autorizado"
        ) {
          await db
            .prepare(
              `UPDATE facturas
               SET estado = 'rechazada',
                   motivo_rechazo = ?,
                   sri_estado_bruto = ?,
                   ruc_emisor = COALESCE(?, ruc_emisor),
                   nombre_comprador_factura = COALESCE(?, nombre_comprador_factura),
                   fecha_factura = COALESCE(?, fecha_factura),
                   monto_total = COALESCE(?, monto_total)
               WHERE id = ?`
            )
            .bind(
              `SRI respondió: ${sriResult.estado}`,
              sriResult.estado,
              sriResult.ruc_emisor,
              sriResult.nombre_comprador,
              sriResult.fecha_autorizacion,
              sriResult.monto,
              existingPending.id
            )
            .run();

          return c.json(
            {
              factura_id: existingPending.id,
              estado: "rechazada",
              motivo_rechazo: `SRI respondió: ${sriResult.estado}`,
              sri_estado: sriResult.estado,
            },
            200
          );
        }

        const nombreUsuario = await db
          .prepare("SELECT nombre_completo FROM usuarios WHERE id = ?")
          .bind(user.sub)
          .first<{ nombre_completo: string }>();

        const nombreFactura = sriResult.nombre_comprador;
        const nombreReal = nombreUsuario?.nombre_completo;

        let nuevoEstado: string;
        let nuevoMotivo: string | null = null;

        if (
          nombreFactura &&
          nombreReal &&
          nombreFactura.toUpperCase() !== nombreReal.toUpperCase()
        ) {
          nuevoEstado = "pendiente_revision_nombre";
          nuevoMotivo =
            "Nombre en factura no coincide con el nombre del usuario";
        } else {
          nuevoEstado = "aprobada";
        }

        await db
          .prepare(
            `UPDATE facturas
             SET estado = ?,
                 motivo_rechazo = ?,
                 sri_estado_bruto = ?,
                 ruc_emisor = COALESCE(?, ruc_emisor),
                 nombre_comprador_factura = COALESCE(?, nombre_comprador_factura),
                 fecha_factura = COALESCE(?, fecha_factura),
                 monto_total = COALESCE(?, monto_total)
             WHERE id = ?`
          )
          .bind(
            nuevoEstado,
            nuevoMotivo,
            sriResult.estado,
            sriResult.ruc_emisor,
            sriResult.nombre_comprador,
            sriResult.fecha_autorizacion,
            sriResult.monto,
            existingPending.id
          )
          .run();

        return c.json(
          {
            factura_id: existingPending.id,
            estado: nuevoEstado,
            motivo_rechazo: nuevoMotivo,
            sri_estado: sriResult.estado,
          },
          200
        );
      }

      if (
        enforce &&
        (sriResult.estado === "rechazada" ||
          sriResult.estado === "no_autorizado")
      ) {
        const duplicate = await insertRechazada(
          `SRI respondió: ${sriResult.estado}`,
          sriResult.estado
        );
        if (duplicate) return duplicate;
        return c.json(
          {
            error: `Factura ${sriResult.estado} por el SRI`,
            detalle: sriResult.mensaje_sri,
          },
          422
        );
      }

      let estado: string;
      let motivo_rechazo: string | null = null;
      if (!enforce) {
        estado = "aprobada";
      } else if (sriResult.estado === "servicio_no_disponible") {
        estado = "pendiente_verificacion_sri";
        motivo_rechazo = "SRI no disponible";
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
          motivo_rechazo = "Nombre en factura no coincide con el nombre del usuario";
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
               fecha_factura, monto_total, estado, motivo_rechazo, sri_estado_bruto)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
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
            motivo_rechazo,
            sriResult.estado
          )
          .run();

        return c.json(
          {
            factura_id: result.meta.last_row_id,
            estado,
            motivo_rechazo,
            sri_estado: sriResult.estado,
          },
          201
        );
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        if (!msg.includes("UNIQUE constraint failed")) {
          throw err;
        }
        return c.json(
          { error: "Esta clave ya fue registrada o intentada anteriormente" },
          409
        );
      }
    }

    const result = await db
      .prepare(
        `INSERT INTO facturas
          (cliente_id, comercio_id, evento_id, nivel_verificacion,
           numero_factura, ruc_emisor, nombre_comprador_factura,
           fecha_factura, monto_total, estado, motivo_rechazo)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
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
        body.nivel_verificacion === 2
          ? "pendiente_revision_nombre"
          : "aprobada",
        body.nivel_verificacion === 2
          ? "Comprobante verificado por OCR, pendiente validación"
          : null
      )
      .run();

    const estado = body.nivel_verificacion === 2
      ? "pendiente_revision_nombre"
      : "aprobada";

    return c.json({ factura_id: result.meta.last_row_id, estado }, 201);
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
                descuento_aplicado, estado, motivo_rechazo, created_at
         FROM facturas
         WHERE cliente_id = ?
         ORDER BY created_at DESC`
      )
      .bind(user.sub)
      .all();

    return c.json({ facturas: result.results });
  }
);

  return facturas;
}

export const facturas = createFacturas();
