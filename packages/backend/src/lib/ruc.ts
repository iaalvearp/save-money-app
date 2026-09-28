/**
 * Validación del RUC de Ecuador.
 *
 * Un RUC son 13 dígitos y se lee por partes:
 *
 *   P P T ........ E E E
 *   │ │ │           └── 3 dígitos del establecimiento. Va de 001 a 999, porque
 *   │ │ │               el 000 no existe como código de establecimiento.
 *   │ │ └────────────── los 10 dígitos de la cédula (persona natural) o del
 *   │ │                  RUC (persona jurídica). El último es el verificador.
 *   │ └──────────────── el tercer dígito dice qué tipo de contribuyente es.
 *   └────────────────── los 2 primeros son el código de provincia: 01 a 24,
 *                       más el 30 de Galápagos.
 *
 * El tercer dígito define el algoritmo del dígito verificador:
 *
 *   0 a 5 → persona natural. Los 10 primeros dígitos son una cédula y se
 *           valida con el algoritmo módulo 10, que pondera del 2 al 9 según
 *           la posición y toma el residuo de 10.
 *   6     → sector público (ministerios, municipalidades). Valida
 *           con módulo 11 sobre los 9 primeros dígitos, con los coeficientes
 *           3 2 7 6 5 4 3 2, y el dígito 9 es el verificador.
 *   9     → persona jurídica (empresas). Valida con módulo 11 sobre los 10
 *           primeros dígitos, con los coeficientes 4 3 2 7 6 5 4 3 2, y el
 *           dígito 10 es el verificador.
 *   7 y 8 → no corresponden a un tipo de contribuyente válido.
 *
 * Fuente: Servicio de Rentas Internas (SRI) del Ecuador, "Formato del RUC" y
 * algoritmo de verificación del dígito verificador (módulo 10 para cédula,
 * módulo 11 para RUC). En módulo 11, si el residuo es 10 el verificador es 0;
 * si es 11, el verificador es 1.
 */

/** Códigos de provincia válidos: 01 a 24 más el 30 (Galápagos). */
function provinciaValida(provincia: number): boolean {
  return (provincia >= 1 && provincia <= 24) || provincia === 30;
}

/**
 * Verificador de una cédula de 10 dígitos.
 *
 * Los primeros 9 dígitos se multiplican por los pesos 2, 3, 4, 5, 6, 7, 8, 9
 * y 2 (el ciclo vuelve a 2 en el noveno dígito). El residuo de dividir la suma
 * entre 10 da el verificador: si es 0, el dígito es 0; si no, es 10 menos el
 * residuo.
 */
function verificadorCedula(cedula: string): number {
  let suma = 0;
  for (let i = 0; i < 9; i++) {
    suma += Number(cedula[i]) * (i === 8 ? 2 : i + 2);
  }
  const residuo = suma % 10;
  return residuo === 0 ? 0 : 10 - residuo;
}

/** Verificador módulo 11 con los coeficientes indicados sobre los primeros digitos. */
function verificadorModulo11(digitos: string, coeficientes: number[]): number {
  let suma = 0;
  for (let i = 0; i < coeficientes.length; i++) {
    suma += Number(digitos[i]) * coeficientes[i];
  }
  const residuo = suma % 11;
  // El SRI define 0 para el residuo 10 y 1 para el residuo 11.
  if (residuo === 10) return 0;
  if (residuo === 11) return 1;
  return residuo;
}

const COEFICIENTES_SECTOR_PUBLICO = [3, 2, 7, 6, 5, 4, 3, 2];
const COEFICIENTES_PERSONA_JURIDICA = [4, 3, 2, 7, 6, 5, 4, 3, 2];

/**
 * Revisa un RUC. Devuelve `null` si es correcto, o el motivo en español por
 * el que no lo es. El mensaje va directo al usuario, asi que dice qué está
 * mal y no solo "RUC inválido".
 */
export function motivoRucInvalido(ruc: string | null | undefined): string | null {
  if (ruc === null || ruc === undefined) {
    return null;
  }

  const valor = String(ruc).trim();

  if (valor === "") {
    return null;
  }

  if (!/^\d{13}$/.test(valor)) {
    return "El RUC debe tener 13 dígitos, solo números";
  }

  const provincia = Number(valor.slice(0, 2));
  if (!provinciaValida(provincia)) {
    return "El RUC no corresponde a una provincia del Ecuador válida (código entre 01 y 24, o 30 para Galápagos)";
  }

  const tipo = Number(valor[2]);
  if (tipo === 7 || tipo === 8) {
    return "El tercer dígito del RUC debe ser 0 a 5 para personas naturales, 6 para el sector público o 9 para personas jurídicas";
  }

  const establecimiento = Number(valor.slice(10));
  if (establecimiento < 1) {
    return "El número de establecimiento del RUC debe ser 001 o mayor";
  }

  if (tipo < 6) {
    // Persona natural: los 10 primeros dígitos son la cédula.
    const cedula = valor.slice(0, 10);
    if (verificadorCedula(cedula) !== Number(cedula[9])) {
      return "El RUC no es válido: el dígito verificador de la cédula no coincide";
    }
    return null;
  }

  if (tipo === 6) {
    // Sector público: módulo 11 sobre los dígitos 1 a 8, con el dígito 9
    // como verificador.
    const esperado = verificadorModulo11(valor, COEFICIENTES_SECTOR_PUBLICO);
    if (esperado !== Number(valor[8])) {
      return "El RUC no es válido: el dígito verificador del sector público no coincide";
    }
    return null;
  }

  // Persona jurídica: módulo 11 sobre los dígitos 1 a 9, con el dígito 10
  // como verificador.
  const esperado = verificadorModulo11(valor, COEFICIENTES_PERSONA_JURIDICA);
  if (esperado !== Number(valor[9])) {
    return "El RUC no es válido: el dígito verificador de la persona jurídica no coincide";
  }
  return null;
}

/** `true` si el RUC es correcto o no se envió ninguno. */
export function rucValido(ruc: string | null | undefined): boolean {
  return motivoRucInvalido(ruc) === null;
}

/**
 * Revisa el horario de un comercio. Devuelve `null` si está bien, o el motivo.
 * La hora de cierre tiene que ser posterior a la de apertura: un local que
 * cierra antes de abrir no tiene sentido.
 */
export function motivoHorarioInvalido(
  horaApertura: string | null | undefined,
  horaCierre: string | null | undefined
): string | null {
  const formato = /^\d{2}:\d{2}$/;

  if (horaApertura !== null && horaApertura !== undefined) {
    if (!formato.test(horaApertura)) {
      return "La hora de apertura debe tener el formato HH:MM";
    }
    if (Number(horaApertura.slice(3)) > 59) {
      return "La hora de apertura no es una hora válida";
    }
  }

  if (horaCierre !== null && horaCierre !== undefined) {
    if (!formato.test(horaCierre)) {
      return "La hora de cierre debe tener el formato HH:MM";
    }
    if (Number(horaCierre.slice(3)) > 59) {
      return "La hora de cierre no es una hora válida";
    }
  }

  if (
    horaApertura &&
    horaCierre &&
    horaCierre <= horaApertura
  ) {
    return "La hora de cierre debe ser posterior a la hora de apertura";
  }

  return null;
}
