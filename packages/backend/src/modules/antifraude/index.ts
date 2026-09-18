/**
 * Módulo centralizado de antifraude.
 *
 * Responsabilidades:
 * 1. Detectar duplicados por nivel de verificación.
 * 2. Validar que la compra esté dentro del horario del evento.
 * 3. Determinar si el estado permite generar beneficios.
 *
 * Rechazo automático:
 * - Clave SRI duplicada (nivel 1)
 * - Ticket físico duplicado: misma {comercio_id, numero_factura, ruc_emisor,
 *   fecha_factura, monto_total} (nivel 2/3)
 * - Compra fuera del horario del evento
 *
 * Revisión manual (pendiente_revision_nombre):
 * - Nombre en factura/SRI no coincide con el nombre del usuario
 * - Nivel 2 (OCR): pendiente validación de contenido
 * - Nivel 3 (sin comprobante): pendiente validación de claim
 */

export interface DuplicadoResult {
  esDuplicado: boolean;
  facturaId?: number;
  motivo?: string;
}

export interface HorarioEventoResult {
  valido: boolean;
  motivo?: string;
}

/**
 * Verifica si una clave SRI ya fue registrada (nivel 1).
 */
export async function verificarDuplicadoSRI(
  db: D1Database,
  claveAcceso: string
): Promise<DuplicadoResult> {
  const existing = await db
    .prepare(
      `SELECT id, estado FROM facturas
       WHERE clave_acceso_49 = ?
       AND estado NOT IN ('rechazada')`
    )
    .bind(claveAcceso)
    .first<{ id: number; estado: string }>();

  if (existing) {
    return {
      esDuplicado: true,
      facturaId: existing.id,
      motivo: `Clave SRI ya registrada con estado "${existing.estado}"`,
    };
  }

  return { esDuplicado: false };
}

/**
 * Verifica si un ticket físico ya fue registrado (nivel 2/3).
 * Identidad de duplicado: misma combinación de comercio + número de factura
 * + RUC emisor + fecha + monto, excluyendo rechazados.
 */
export async function verificarDuplicadoTicket(
  db: D1Database,
  params: {
    clienteId: number;
    comercioId?: number | null;
    numeroFactura?: string | null;
    rucEmisor?: string | null;
    fechaFactura?: string | null;
    montoTotal?: number | null;
  }
): Promise<DuplicadoResult> {
  if (!params.numeroFactura && !params.rucEmisor) {
    return { esDuplicado: false };
  }

  const conditions: string[] = [
    "nivel_verificacion IN (2, 3)",
    "estado NOT IN ('rechazada')",
  ];
  const binds: unknown[] = [];

  if (params.comercioId != null) {
    conditions.push("comercio_id = ?");
    binds.push(params.comercioId);
  } else {
    conditions.push("comercio_id IS NULL");
  }

  if (params.numeroFactura != null) {
    conditions.push("numero_factura = ?");
    binds.push(params.numeroFactura);
  } else {
    conditions.push("numero_factura IS NULL");
  }

  if (params.rucEmisor != null) {
    conditions.push("ruc_emisor = ?");
    binds.push(params.rucEmisor);
  } else {
    conditions.push("ruc_emisor IS NULL");
  }

  if (params.fechaFactura != null) {
    conditions.push("fecha_factura = ?");
    binds.push(params.fechaFactura);
  } else {
    conditions.push("fecha_factura IS NULL");
  }

  if (params.montoTotal != null) {
    conditions.push("monto_total = ?");
    binds.push(params.montoTotal);
  } else {
    conditions.push("monto_total IS NULL");
  }

  const query = `
    SELECT id, cliente_id, estado FROM facturas
    WHERE ${conditions.join(" AND ")}
    LIMIT 1
  `;

  const existing = await db
    .prepare(query)
    .bind(...binds)
    .first<{ id: number; cliente_id: number; estado: string }>();

  if (existing) {
    const mismoUsuario = existing.cliente_id === params.clienteId;
    return {
      esDuplicado: true,
      facturaId: existing.id,
      motivo: mismoUsuario
        ? "Este ticket ya fue registrado previamente"
        : "Este ticket fue registrado por otro usuario",
    };
  }

  return { esDuplicado: false };
}

/**
 * Verifica si la fecha de la compra está dentro del horario del evento.
 * Solo aplica cuando se proporciona evento_id y fecha_factura.
 */
export async function verificarHorarioEvento(
  db: D1Database,
  params: {
    eventoId?: number | null;
    fechaFactura?: string | null;
  }
): Promise<HorarioEventoResult> {
  if (!params.eventoId || !params.fechaFactura) {
    return { valido: true };
  }

  const evento = await db
    .prepare(
      "SELECT fecha_inicio, fecha_fin FROM eventos WHERE id = ?"
    )
    .bind(params.eventoId)
    .first<{ fecha_inicio: string; fecha_fin: string }>();

  if (!evento) {
    return {
      valido: false,
      motivo: "El evento especificado no existe",
    };
  }

  const fechaCompra = new Date(params.fechaFactura);
  const fechaInicio = new Date(evento.fecha_inicio);
  const fechaFin = new Date(evento.fecha_fin);

  if (fechaCompra < fechaInicio || fechaCompra > fechaFin) {
    return {
      valido: false,
      motivo: `La fecha de la compra (${params.fechaFactura}) está fuera del rango del evento (${evento.fecha_inicio} a ${evento.fecha_fin})`,
    };
  }

  return { valido: true };
}

/**
 * Verifica si un estado permite generar beneficios.
 * Solo "aprobada" permite descuentos, puntos y acceso a premios.
 */
export function estadoPermiteBeneficios(estado: string): boolean {
  return estado === "aprobada";
}

/**
 * Determina el estado y motivo iniciales para una nueva factura
 * basándose en el nivel de verificación.
 */
export function estadoInicialNivel(
  nivelVerificacion: number,
  motivoOverride?: string
): { estado: string; motivo_rechazo: string | null } {
  switch (nivelVerificacion) {
    case 1:
      return { estado: "aprobada", motivo_rechazo: null };
    case 2:
      return {
        estado: "pendiente_revision_nombre",
        motivo_rechazo:
          motivoOverride ||
          "Comprobante verificado por OCR, pendiente validación",
      };
    case 3:
      return {
        estado: "pendiente_revision_nombre",
        motivo_rechazo:
          motivoOverride ||
          "Compra declarada sin comprobante, pendiente validación",
      };
    default:
      return { estado: "aprobada", motivo_rechazo: null };
  }
}
