import type { D1Database } from "@cloudflare/workers-types";
import { instanteDeCompra } from "../../lib/fechas";

/**
 * Cuantas compras cuenta una persona para un premio por frecuencia.
 *
 * La regla de negocio es: cuentan las compras aprobadas que hizo en un
 * comercio patrocinador del evento, dentro de la ventana de tiempo del premio.
 * Si el premio pertenece a una ronda, la ventana son las horas de esa ronda; si
 * no, es la ventana completa del evento.
 */

/** Lo que hay que saber de un premio para poder contar. */
export interface PremioParaContar {
  id: number;
  evento_id: number;
  ronda_id: number | null;
  criterio_frecuencia: number | null;
  tipo: string;
}

/** El resultado del conteo, con lo que no se pudo leer a la vista. */
export interface ConteoCompras {
  /** Compras que cuentan de verdad. */
  compras: number;
  /** Cuantas hacen falta, o null si el premio no es de frecuencia. */
  criterio: number | null;
  /** Si ya se cumplio el criterio. */
  cumple: boolean;
  /** Ventana que se aplico, para poder explicarsela a quien pregunta. */
  ventana: string;
  /**
   * Compras aprobadas que existen pero cuya fecha no se pudo interpretar.
   * No cuentan, y no hacen fallar nada: se informan para que no sean
   * invisibles.
   */
  sin_fecha_legible: number;
}

/**
 * Las fechas de las que depende el conteo, ya leidas.
 *
 * Se lee una vez y se reutiliza, porque leer la fecha de cada compra por
 * separado repetiria el trabajo para cada una.
 */
interface VentanaLeida {
  desde: number;
  hasta: number;
  etiqueta: string;
}

/**
 * Decide que ventana de tiempo aplica a un premio.
 *
 * Devuelve null si la ventana no se puede leer, porque en ese caso no hay
 * forma honesta de saber que compras cuentan: inventar una ventana haria que
 * la gente perdiera o ganara un premio por error.
 */
async function ventanaDelPremio(
  db: D1Database,
  premio: PremioParaContar
): Promise<VentanaLeida | null> {
  if (premio.ronda_id !== null && premio.ronda_id !== undefined) {
    const ronda = await db
      .prepare("SELECT nombre, hora_inicio, hora_fin FROM rondas WHERE id = ?")
      .bind(premio.ronda_id)
      .first<{ nombre: string; hora_inicio: string; hora_fin: string }>();

    if (!ronda) return null;

    const desde = instanteDeCompra(ronda.hora_inicio);
    const hasta = instanteDeCompra(ronda.hora_fin);
    if (desde === null || hasta === null) return null;

    return {
      desde,
      hasta,
      etiqueta: `ronda "${ronda.nombre}" (${ronda.hora_inicio} a ${ronda.hora_fin})`,
    };
  }

  const evento = await db
    .prepare("SELECT fecha_inicio, fecha_fin FROM eventos WHERE id = ?")
    .bind(premio.evento_id)
    .first<{ fecha_inicio: string; fecha_fin: string }>();

  if (!evento) return null;

  const desde = instanteDeCompra(evento.fecha_inicio);
  const hasta = instanteDeCompra(evento.fecha_fin);
  if (desde === null || hasta === null) return null;

  return {
    desde,
    hasta,
    etiqueta: `evento (${evento.fecha_inicio} a ${evento.fecha_fin})`,
  };
}

/**
 * Cuenta las compras que hacen falta para un premio.
 *
 * Trae las compras de la persona en los comercios patrocinadores del evento y
 * las filtra por fecha aqui, en vez de compararlas en SQL. Es a proposito: las
 * fechas llegan en cuatro formatos distintos segun de donde venga la compra, y
 * compararlas como texto las ordenaria mal.
 */
export async function contarComprasQueCuentan(
  db: D1Database,
  clienteId: number,
  premio: PremioParaContar
): Promise<ConteoCompras> {
  const criterio = premio.criterio_frecuencia;
  const noAplica: ConteoCompras = {
    compras: 0,
    criterio,
    cumple: false,
    ventana: "",
    sin_fecha_legible: 0,
  };

  const ventana = await ventanaDelPremio(db, premio);
  if (ventana === null) return noAplica;

  const compras = await db
    .prepare(
      `SELECT f.fecha_factura AS fecha
       FROM facturas f
       JOIN eventos_sponsors s ON s.comercio_id = f.comercio_id
       WHERE f.cliente_id = ?
         AND f.estado = 'aprobada'
         AND s.evento_id = ?
         AND s.estado = 'aprobado'`
    )
    .bind(clienteId, premio.evento_id)
    .all<{ fecha: string | null }>();

  let comprasQueCuentan = 0;
  let sinFecha = 0;

  for (const fila of compras.results ?? []) {
    const instante = instanteDeCompra(fila.fecha);
    // Una compra sin fecha legible no se puede colocar en el tiempo, asi que no
    // cuenta. No es un error: el reclamo sigue adelante con las demas.
    if (instante === null) {
      sinFecha++;
      continue;
    }
    if (instante >= ventana.desde && instante <= ventana.hasta) {
      comprasQueCuentan++;
    }
  }

  return {
    compras: comprasQueCuentan,
    criterio,
    cumple: criterio !== null && comprasQueCuentan >= criterio,
    ventana: ventana.etiqueta,
    sin_fecha_legible: sinFecha,
  };
}
