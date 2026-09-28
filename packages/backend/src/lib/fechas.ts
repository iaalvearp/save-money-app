/**
 * Lectura de las fechas que llegan desde el movil.
 *
 * La app guarda cada fecha en un formato distinto segun de donde venga, y el
 * backend las recibe tal cual. Ordenar esas cadenas de texto no funciona: no
 * respeta el orden real y no se pueden restar dos ventanas. Aqui cada fecha se
 * convierte a un numero, que si permite comparar y restar.
 *
 * Hay dos maneras distintas de contar el tiempo, y confundirlas es el origen
 * del bug que se corrigio con este archivo:
 *
 * - `instanteDeCompra` para las fechas con hora real, las del reloj de quien
 *   compro. Ahi si importa el momento exacto, asi que se lee como instante
 *   absoluto.
 * - `diaComoCalendario` para las ventanas de negocio, las del evento y de la
 *   ronda. "La ronda abre a las 10:00" significa las 10 de la manana donde
 *   esta la gente, no las 10 UTC. Por eso se cuentan dias calendario, con la
 *   hora de Ecuador, y no instantes.
 */

/** Ecuador no aplica horario de verano: su offset es siempre -05:00. */
const OFFSET_ECUADOR_MINUTOS = -300;

/** 2026-03-01T10:00:00-05:00, con Z o con offset numerico. */
const ISO_CON_ZONA =
  /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?(?:\.\d+)?(Z|[+-]\d{2}:?\d{2})$/i;

/** 2026-03-01 10:00:00, sin zona. */
const FECHA_HORA_SIN_ZONA =
  /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?(?:\.\d+)?$/;

/** 2026-03-01, sin hora. */
const FECHA_SIN_HORA = /^(\d{4})-(\d{2})-(\d{2})$/;

/** 01/03/2026, el formato del OCR. */
const DIA_MES_ANIO = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/;

/** 1-3-26, el formato de la compra declarada a mano. */
const DIA_MES_ANIO_CORTOS = /^(\d{1,2})-(\d{1,2})-(\d{2})$/;

/** Comprueba que el dia exista de verdad en ese mes. */
function fechaExiste(anio: number, mes: number, dia: number): boolean {
  if (mes < 1 || mes > 12 || dia < 1 || dia > 31) return false;
  // El dia 0 es el ultimo del mes anterior, asi que asi se detecta el 31 de
  // febrero sin tener que escribir una tabla de meses.
  return dia <= new Date(Date.UTC(anio, mes, 0)).getUTCDate();
}

/** Las tres partes de una fecha, ya validadas. */
type Partes = { anio: number; mes: number; dia: number };

/**
 * Separa cualquier formato admitido en sus tres numeros, o devuelve null.
 *
 * Se validan aqui el rango del dia y del mes, asi que quien reciba un numero no
 * nulo ya sabe que la fecha existe.
 */
function partes(valor: string | null | undefined): Partes | null {
  if (typeof valor !== "string") return null;
  const texto = valor.trim();
  if (texto === "") return null;

  const soloFecha = FECHA_SIN_HORA.exec(texto);
  if (soloFecha) {
    const [, a, m, d] = soloFecha;
    return validar(Number(a), Number(m), Number(d));
  }

  // Una fecha con hora dice tambien que dia es, y en las ventanas de negocio
  // la hora se ignora: se decide por dia, no por reloj.
  const conZona = ISO_CON_ZONA.exec(texto);
  if (conZona) {
    const [, a, m, d] = conZona;
    return validar(Number(a), Number(m), Number(d));
  }

  const conHoraSinZona = FECHA_HORA_SIN_ZONA.exec(texto);
  if (conHoraSinZona) {
    const [, a, m, d] = conHoraSinZona;
    return validar(Number(a), Number(m), Number(d));
  }

  const diaMesAnio = DIA_MES_ANIO.exec(texto);
  if (diaMesAnio) {
    const [, d, m, a] = diaMesAnio;
    return validar(Number(a), Number(m), Number(d));
  }

  const corto = DIA_MES_ANIO_CORTOS.exec(texto);
  if (corto) {
    const [, d, m, a] = corto;
    return validar(anioDelSigloActual(Number(a)), Number(m), Number(d));
  }

  return null;
}

function validar(anio: number, mes: number, dia: number): Partes | null {
  if (!fechaExiste(anio, mes, dia)) return null;
  return { anio, mes, dia };
}

/** Mediodia en UTC del dia, en minutos desde epoch. */
function minutosDeMediodia({ anio, mes, dia }: Partes): number {
  return Math.floor(Date.UTC(anio, mes - 1, dia, 12) / 60000);
}

/** Primer instante del dia en Ecuador, en milisegundos desde epoch. */
function medianocheEnEcuador({ anio, mes, dia }: Partes): number {
  return Date.UTC(anio, mes - 1, dia) - OFFSET_ECUADOR_MINUTOS * 60000;
}

/** Anio de dos digitos: 26 es 2026, nunca 1926. */
function anioDelSigloActual(anioCorto: number): number {
  return 2000 + anioCorto;
}

/** Convierte una hora sin zona a instante, asumiendo que es hora de Ecuador. */
function instanteEnEcuador(
  anio: number,
  mes: number,
  dia: number,
  hora: number,
  minuto: number,
  segundo: number
): number | null {
  if (!fechaExiste(anio, mes, dia)) return null;
  if (hora > 23 || minuto > 59 || segundo > 59) return null;
  return (
    Date.UTC(anio, mes - 1, dia, hora, minuto, segundo) -
    OFFSET_ECUADOR_MINUTOS * 60 * 1000
  );
}

/** Quita el offset de una fecha con zona y devuelve su base en UTC. */
function instanteDeIsoConZona(captura: RegExpExecArray): number | null {
  const [, a, m, d, h, mi, s = "00", zona] = captura;
  const anio = Number(a);
  const mes = Number(m);
  const dia = Number(d);
  if (!fechaExiste(anio, mes, dia)) return null;
  if (Number(h) > 23 || Number(mi) > 59 || Number(s) > 59) return null;

  const base = Date.UTC(anio, mes - 1, dia, Number(h), Number(mi), Number(s));
  if (zona.toUpperCase() === "Z") return base;

  const signo = zona.startsWith("-") ? -1 : 1;
  const digitos = zona.slice(1).replace(":", "");
  const offsetEnMinutos =
    Number(digitos.slice(0, 2)) * 60 + Number(digitos.slice(2, 4));
  return base - signo * offsetEnMinutos * 60000;
}

/**
 * Lee la fecha de una compra, la del reloj de quien la hizo.
 *
 * Acepta el ISO con offset que manda el SRI, y tambien las fechas sin zona que
 * llegan del movil, asumiendo que estan escritas en hora de Ecuador.
 *
 * Devuelve milisegundos desde epoch, o null si la fecha no existe o el formato
 * no es uno de los conocidos. Un null no es un error: significa que esa compra
 * no se puede colocar en el tiempo, y el codigo que la use decide que hacer.
 */
export function instanteDeCompra(
  valor: string | null | undefined
): number | null {
  if (typeof valor !== "string") return null;
  const texto = valor.trim();
  if (texto === "") return null;

  const conZona = ISO_CON_ZONA.exec(texto);
  if (conZona) return instanteDeIsoConZona(conZona);

  const sinZona = FECHA_HORA_SIN_ZONA.exec(texto);
  if (sinZona) {
    const [, a, m, d, h, mi, s = "00"] = sinZona;
    return instanteEnEcuador(
      Number(a),
      Number(m),
      Number(d),
      Number(h),
      Number(mi),
      Number(s)
    );
  }

  // Una fecha sin hora no tiene momento exacto, solo un dia. Se usa el primer
  // instante de ese dia en Ecuador, que es lo unico que se puede afirmar.
  const delDia = partes(texto);
  if (delDia === null) return null;
  return medianocheEnEcuador(delDia);
}

/**
 * Lee una fecha y la deja en un dia calendario de Ecuador.
 *
 * Se usa para las ventanas del evento y de la ronda. Devuelve minutos desde
 * epoch del mediodia, no del inicio del dia, para que ningun desfase horario
 * pueda mover la fecha al dia de al lado.
 */
export function diaComoCalendario(
  valor: string | null | undefined
): number | null {
  const delDia = partes(valor);
  if (delDia === null) return null;
  return minutosDeMediodia(delDia);
}

/** Si un valor se puede leer como fecha, sea del formato que sea. */
export function esFechaLegible(valor: string | null | undefined): boolean {
  return diaComoCalendario(valor) !== null;
}
