import type { D1Database } from "@cloudflare/workers-types";

interface EmitirCuponParams {
  db: D1Database;
  comercioId: number;
  clienteId: number;
  descuento: number;
  expiraEn: string;
  tipo: "flash" | "hunt";
  emitidoPor?: number;
}

export interface CuponConComercio {
  id: number;
  codigo_qr: string;
  descuento: number | null;
  estado: string;
  tipo: string;
  expira_en: string | null;
  canjeado_en: string | null;
  created_at: string;
  comercio_nombre: string;
  comercio_foto: string | null;
}

function generateQrCode(tipo: string): string {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  const prefix = tipo === "flash" ? "FLASH" : "HUNT";
  let result = `${prefix}-`;
  for (let i = 0; i < 12; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}

export async function emitirCupon(
  params: EmitirCuponParams
): Promise<{ id: number; codigo_qr: string }> {
  const { db, comercioId, clienteId, descuento, expiraEn, tipo, emitidoPor } =
    params;

  const codigoQr = generateQrCode(tipo);

  const result = await db
    .prepare(
      `INSERT INTO cupones
       (comercio_id, cliente_id, codigo_qr, estado, tipo, descuento, expira_en, emitido_por)
       VALUES (?, ?, ?, 'activo', ?, ?, ?, ?)`
    )
    .bind(
      comercioId,
      clienteId,
      codigoQr,
      tipo,
      descuento,
      expiraEn,
      emitidoPor ?? null
    )
    .run();

  return { id: result.meta.last_row_id as number, codigo_qr: codigoQr };
}

export async function listarCuponesDeUsuario(
  db: D1Database,
  clienteId: number
): Promise<CuponConComercio[]> {
  await db
    .prepare(
      `UPDATE cupones SET estado = 'expirado'
       WHERE cliente_id = ? AND estado = 'activo'
       AND expira_en IS NOT NULL AND expira_en < datetime('now')`
    )
    .bind(clienteId)
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
    .bind(clienteId)
    .all();

  return result.results as CuponConComercio[];
}

export async function canjearCupon(
  db: D1Database,
  cuponId: number,
  comercioId: number
): Promise<{ ok: boolean; error?: string }> {
  const cupon = await db
    .prepare(
      `SELECT cu.id, cu.estado, cu.expira_en, cu.comercio_id
       FROM cupones cu WHERE cu.id = ?`
    )
    .bind(cuponId)
    .first<{
      id: number;
      estado: string;
      expira_en: string | null;
      comercio_id: number;
    }>();

  if (!cupon) {
    return { ok: false, error: "Cupon no encontrado" };
  }

  if (cupon.comercio_id !== comercioId) {
    return { ok: false, error: "Cupon no pertenece a este comercio" };
  }

  if (cupon.estado !== "activo") {
    return { ok: false, error: `Cupon ya fue ${cupon.estado}` };
  }

  if (cupon.expira_en && new Date(cupon.expira_en) < new Date()) {
    await db
      .prepare("UPDATE cupones SET estado = 'expirado' WHERE id = ?")
      .bind(cuponId)
      .run();
    return { ok: false, error: "Cupon expirado" };
  }

  const now = new Date().toISOString().replace("T", " ").slice(0, 19);
  const updateResult = await db
    .prepare(
      `UPDATE cupones SET estado = 'utilizado', canjeado_en = ?
       WHERE id = ? AND estado = 'activo'`
    )
    .bind(now, cuponId)
    .run();

  if (updateResult.meta.changes === 0) {
    return { ok: false, error: "Cupon ya fue canjeado" };
  }

  return { ok: true };
}
