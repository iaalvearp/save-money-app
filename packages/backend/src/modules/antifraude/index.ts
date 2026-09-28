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

import {
  diaComoCalendario,
  instanteDeCompra,
  instanteEnVentana,
  traeHora,
} from "../../lib/fechas";

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

  return compararConElHorarioDelEvento(params.fechaFactura, evento);
}

/**
 * Decide si una compra cae dentro de la ventana de un evento.
 *
 * Antes esto comparaba con `new Date()`, que no entiende los formatos que
 * llegan del movil. Con 01/03/2026 o 1-3-26 la comparacion daba NaN, y como
 * cualquier comparacion con NaN es falsa, la validacion pasaba siempre: no
 * habia forma de que un evento rechazara una compra fuera de su horario.
 *
 * Ahora hay dos comparaciones, segun lo que sepa la fecha de la compra:
 *
 * - Con hora, que es lo que llega del SRI, se comparan instantes. Una compra
 *   de las 07:00 no es valida en un evento que abre a las 08:00, aunque sea del
 *   mismo dia.
 * - Solo con dia, que es lo que llega del OCR y de la compra declarada, se
 *   comparan dias calendario. No se puede afirmar que una compra fue antes de
 *   que abriera algo que no sabemos a que hora abrio, asi que se toma el dia
 *   completo.
 *
 * Cuando la fecha de la compra no se puede leer no se bloquea. Bloquear a
 * alguien por una fecha que el sistema no entiende seria rechazar una compra
 * legitima, y la compra se aprueba igualmente por otros motivos.
 */
function compararConElHorarioDelEvento(
  fechaFactura: string,
  evento: { fecha_inicio: string; fecha_fin: string }
): HorarioEventoResult {
  const fueraDeRango = `La fecha de la compra (${fechaFactura}) está fuera del rango del evento (${evento.fecha_inicio} a ${evento.fecha_fin})`;

  if (traeHora(fechaFactura)) {
    const compra = instanteDeCompra(fechaFactura);
    if (compra === null) {
      // Dice que trae hora pero la hora no existe, como 25:00. Es una fecha que
      // no se puede leer, y por lo mismo no se bloquea.
      return { valido: true };
    }
    return instanteEnVentana(compra, evento.fecha_inicio, evento.fecha_fin)
      ? { valido: true }
      : { valido: false, motivo: fueraDeRango };
  }

  const compraDia = diaComoCalendario(fechaFactura);
  if (compraDia === null) {
    return { valido: true };
  }

  const inicioDia = diaComoCalendario(evento.fecha_inicio);
  const finDia = diaComoCalendario(evento.fecha_fin);
  if (inicioDia === null || finDia === null) {
    // Las fechas del evento tampoco se pueden leer. Sin ventana conocida no se
    // puede afirmar que una compra este fuera, asi que no se bloquea.
    return { valido: true };
  }

  return compraDia >= inicioDia && compraDia <= finDia
    ? { valido: true }
    : { valido: false, motivo: fueraDeRango };
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
