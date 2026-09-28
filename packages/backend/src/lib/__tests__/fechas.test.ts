import { describe, it, expect } from "vitest";
import {
  instanteDeCompra,
  diaComoCalendario,
  esFechaLegible,
  instanteEnVentana,
  instanteEnTextoUtc,
  ahoraEnUtc,
  traeHora,
  partesDeFecha,
  calendarioEcuador,
} from "../fechas";

/** Ecuador: el mediodia son las 17:00 UTC, porque va cinco horas atras. */
const MEDIODIA_ECUADOR_UTC = 17;

/** Minutos que lleva Ecuador por delante de UTC. */
const DESFASE_ECUADOR = 300;

describe("instanteDeCompra", () => {
  it("lee el ISO con offset que manda el SRI como instante absoluto", () => {
    // 10:00 en Quito son las 15:00 UTC, porque Ecuador va cinco horas atras.
    const resultado = instanteDeCompra("2026-03-01T10:00:00-05:00");

    expect(resultado).toBe(Date.UTC(2026, 2, 1, 15, 0, 0));
  });

  it("respetal el offset que trae, no un Ecuador fijo", () => {
    // La misma hora escrita en dos zonas distintas son instantes distintos:
    // las 10:00 de Madrid son las 9:00 UTC, seis horas antes que Quito.
    const quito = instanteDeCompra("2026-03-01T10:00:00-05:00");
    const madrid = instanteDeCompra("2026-03-01T10:00:00+01:00");

    expect(madrid! - quito!).toBe(-6 * 60 * 60 * 1000);
  });

  it("acepta la Z de ISO", () => {
    expect(instanteDeCompra("2026-03-01T15:00:00Z")).toBe(
      instanteDeCompra("2026-03-01T10:00:00-05:00")
    );
  });

  it("acepta el offset sin dos puntos", () => {
    expect(instanteDeCompra("2026-03-01T10:00:00-0500")).toBe(
      instanteDeCompra("2026-03-01T10:00:00-05:00")
    );
  });

  it("asume Ecuador cuando la fecha viene sin zona", () => {
    // Esto es lo que mandan el OCR y la compra declarada, sin transformacion.
    const resultado = instanteDeCompra("2026-03-01 10:00:00");

    expect(resultado).toBe(Date.UTC(2026, 2, 1, 15, 0, 0));
  });

  it("trata el formato del OCR como Ecuador", () => {
    // Medianoche en Quito son las 05:00 UTC del 1 de marzo, no la vispera.
    expect(instanteDeCompra("01/03/2026")).toBe(
      Date.UTC(2026, 2, 1) + DESFASE_ECUADOR * 60000
    );
  });

  it("trata el formato de la compra declarada como Ecuador", () => {
    expect(instanteDeCompra("1-3-26")).toBe(
      Date.UTC(2026, 2, 1) + DESFASE_ECUADOR * 60000
    );
  });

  it("lee los dos digitos del anio como este siglo", () => {
    // 26 es 2026. Si se leyera como 1926 la fecha caeria 100 años atras.
    expect(instanteDeCompra("1-3-26")).toBe(instanteDeCompra("01/03/2026"));
  });

  it("ordena las fechas en el orden real, no en el del texto", () => {
    // Ordenadas como texto, estas dos fechas estan al reves. Ordenadas por
    // instante, '02/01/2026' es la primera: enero antes que marzo.
    const enero = instanteDeCompra("02/01/2026");
    const marzo = instanteDeCompra("01/03/2026");

    expect(enero!).toBeLessThan(marzo!);
  });

  it("devuelve null si la fecha no existe", () => {
    expect(instanteDeCompra("31/02/2026")).toBeNull();
    expect(instanteDeCompra("2026-02-30 10:00:00")).toBeNull();
    expect(instanteDeCompra("2026-13-01T10:00:00Z")).toBeNull();
  });

  it("devuelve null si la hora no existe", () => {
    expect(instanteDeCompra("2026-03-01 25:00:00")).toBeNull();
    expect(instanteDeCompra("2026-03-01 10:70:00")).toBeNull();
  });

  it("devuelve null si falta o no se reconoce", () => {
    expect(instanteDeCompra(null)).toBeNull();
    expect(instanteDeCompra(undefined)).toBeNull();
    expect(instanteDeCompra("")).toBeNull();
    expect(instanteDeCompra("   ")).toBeNull();
    expect(instanteDeCompra("no es una fecha")).toBeNull();
    expect(instanteDeCompra("10:00")).toBeNull();
  });
});

describe("diaComoCalendario", () => {
  it("deja cualquier formato en el mismo dia", () => {
    const referencia = diaComoCalendario("2026-03-01");

    expect(diaComoCalendario("01/03/2026")).toBe(referencia);
    expect(diaComoCalendario("1-3-26")).toBe(referencia);
    expect(diaComoCalendario("2026-03-01 23:59:59")).toBe(referencia);
    expect(diaComoCalendario("2026-03-01T00:00:00-05:00")).toBe(referencia);
    expect(diaComoCalendario("2026-03-01T23:00:00Z")).toBe(referencia);
  });

  it("no deja que el desfase de la zona mueva la fecha de dia", () => {
    // Medianoche en Quito sigue siendo 1 de marzo para quien esta alla. Si se
    // leyera como UTC, esta fecha pasaria al 28 de febrero.
    expect(diaComoCalendario("2026-03-01T00:00:00-05:00")).toBe(
      diaComoCalendario("2026-03-01")
    );
  });

  it("ordena dias consecutivos en orden", () => {
    const treintaEnero = diaComoCalendario("31/01/2026");
    const unoFebrero = diaComoCalendario("01/02/2026");

    // La unidad son minutos, asi que un dia son 1440. Y el 31 de enero es
    // ANTERIOR al 1 de febrero, que es justo lo que hay que comprobar.
    expect(unoFebrero! - treintaEnero!).toBe(1440);
  });

  it("devuelve null si la fecha no existe", () => {
    expect(diaComoCalendario("30/02/2026")).toBeNull();
  });

  it("devuelve null si falta o no se reconoce", () => {
    expect(diaComoCalendario(null)).toBeNull();
    expect(diaComoCalendario("")).toBeNull();
    expect(diaComoCalendario("10:00")).toBeNull();
  });
});

describe("esFechaLegible", () => {
  it("acepta todos los formatos que la app envia", () => {
    expect(esFechaLegible("2026-03-01T10:00:00-05:00")).toBe(true);
    expect(esFechaLegible("2026-03-01 10:00:00")).toBe(true);
    expect(esFechaLegible("01/03/2026")).toBe(true);
    expect(esFechaLegible("1-3-26")).toBe(true);
  });

  it("rechaza lo que no se puede leer", () => {
    expect(esFechaLegible("31/02/2026")).toBe(false);
    expect(esFechaLegible("10:00")).toBe(false);
    expect(esFechaLegible(null)).toBe(false);
  });
});

describe("desfase de Ecuador", () => {
  it("es siempre de cinco horas, sin horario de verano", () => {
    // Comparar una hora de Quito con el mediodia UTC confirma que el desfase
    // es cinco horas todo el ano.
    const mediodiaQuito = new Date(
      instanteDeCompra("2026-01-15 12:00:00")!
    );
    expect(mediodiaQuito.getUTCHours()).toBe(MEDIODIA_ECUADOR_UTC);

    // Tambien en mitad del ano, cuando en otros paises cambia el reloj.
    const mediodiaJulio = new Date(
      instanteDeCompra("2026-07-15 12:00:00")!
    );
    expect(mediodiaJulio.getUTCHours()).toBe(MEDIODIA_ECUADOR_UTC);
  });
});

describe("instanteEnVentana", () => {
  const INICIO = "2026-03-01 10:00:00";
  const FIN = "2026-03-01 18:00:00";

  it("acepta un instante que cae dentro de la ventana", () => {
    // Las 12:00 en Quito caen dentro de una ventana de 10:00 a 18:00.
    const mediodia = instanteDeCompra("2026-03-01 12:00:00");

    expect(instanteEnVentana(mediodia, INICIO, FIN)).toBe(true);
  });

  it("acepta los extremos exactos de la ventana", () => {
    expect(instanteEnVentana(instanteDeCompra(INICIO), INICIO, FIN)).toBe(true);
    expect(instanteEnVentana(instanteDeCompra(FIN), INICIO, FIN)).toBe(true);
  });

  it("rechaza un instante antes de que empiece", () => {
    const temprano = instanteDeCompra("2026-03-01 09:59:59");

    expect(instanteEnVentana(temprano, INICIO, FIN)).toBe(false);
  });

  it("rechaza un instante despues de que acabe", () => {
    const tarde = instanteDeCompra("2026-03-01 18:00:01");

    expect(instanteEnVentana(tarde, INICIO, FIN)).toBe(false);
  });

  it("lee la ventana como hora de Ecuador, no como UTC", () => {
    // Este es el error que se corrigio. Las 10:00 de Quito son las 15:00 UTC,
    // asi que un instante de las 14:55 UTC todavia esta antes de abrir y uno
    // de las 15:05 UTC ya esta dentro. Leyendo la ventana como UTC, el
    // resultado seria el contrario: abriria cinco horas antes de tiempo.
    const cincoMinutosAntesDeAbrirEnUtc = Date.UTC(2026, 2, 1, 14, 55);
    const cincoMinutosDespuesDeAbrirEnUtc = Date.UTC(2026, 2, 1, 15, 5);

    expect(instanteEnVentana(cincoMinutosAntesDeAbrirEnUtc, INICIO, FIN)).toBe(
      false
    );
    expect(instanteEnVentana(cincoMinutosDespuesDeAbrirEnUtc, INICIO, FIN)).toBe(
      true
    );
  });

  it("devuelve false si no se puede leer la ventana", () => {
    const ahora = Date.now();

    expect(instanteEnVentana(ahora, "no es fecha", FIN)).toBe(false);
    expect(instanteEnVentana(ahora, INICIO, "31/02/2026")).toBe(false);
    expect(instanteEnVentana(ahora, null, null)).toBe(false);
  });

  it("devuelve false si el instante a comparar no se conoce", () => {
    expect(instanteEnVentana(null, INICIO, FIN)).toBe(false);
  });
});

describe("instanteEnTextoUtc", () => {
  it("usa el mismo formato que datetime('now')", () => {
    // Sin T y sin milisegundos, que es como los guarda la base de datos.
    expect(instanteEnTextoUtc(Date.UTC(2026, 2, 1, 15, 0, 0))).toBe(
      "2026-03-01 15:00:00"
    );
  });

  it("ahoraEnUtc devuelve un texto con ese mismo formato", () => {
    expect(ahoraEnUtc()).toMatch(/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/);
  });
});

describe("traeHora", () => {
  it("dice que si cuando la fecha dice la hora", () => {
    expect(traeHora("2026-03-01T10:00:00-05:00")).toBe(true);
    expect(traeHora("2026-03-01 10:00:00")).toBe(true);
    expect(traeHora("2026-03-01T15:00:00Z")).toBe(true);
  });

  it("dice que no cuando la fecha solo dice el dia", () => {
    expect(traeHora("2026-03-01")).toBe(false);
    expect(traeHora("01/03/2026")).toBe(false);
    expect(traeHora("1-3-26")).toBe(false);
  });

  it("dice que no cuando no hay fecha", () => {
    expect(traeHora(null)).toBe(false);
    expect(traeHora(undefined)).toBe(false);
    expect(traeHora("")).toBe(false);
    expect(traeHora("   ")).toBe(false);
    expect(traeHora("no es fecha")).toBe(false);
  });
});

describe("partesDeFecha", () => {
  it("devuelve el año, mes y dia tal cual estan escritos en el texto", () => {
    expect(partesDeFecha("2008-01-01")).toEqual({ anio: 2008, mes: 1, dia: 1 });
    expect(partesDeFecha(" 2008-06-30 ")).toEqual({
      anio: 2008,
      mes: 6,
      dia: 30,
    });
  });

  it("acepta una fecha con hora y se queda con su dia", () => {
    expect(partesDeFecha("2008-01-01T23:30:00Z")).toEqual({
      anio: 2008,
      mes: 1,
      dia: 1,
    });
  });

  it("no acepta un dia que no existe en el calendario", () => {
    // El 30 de febrero es el ejemplo clasico: new Date lo normalizaba en
    // silencio a 1 de marzo, y aqui se rechaza.
    expect(partesDeFecha("2008-02-30")).toBeNull();
    expect(partesDeFecha("2008-13-01")).toBeNull();
    expect(partesDeFecha("2007-02-29")).toBeNull();
  });

  it("entiende el formato europeo DD/MM/AAAA, que no es ambiguo", () => {
    // Aceptarlo es una mejora frente a new Date, que devolvia Invalid Date
    // y dejaba la edad en NaN. DD/MM no se confunde con MM/DD, asi que no
    // hay nada que adivinar.
    expect(partesDeFecha("29/05/2008")).toEqual({ anio: 2008, mes: 5, dia: 29 });
    expect(partesDeFecha("01/06/2008")).toEqual({ anio: 2008, mes: 6, dia: 1 });
  });

  it("acepta el 29 de febrero porque 2008 si fue bisiesto", () => {
    expect(partesDeFecha("2008-02-29")).toEqual({ anio: 2008, mes: 2, dia: 29 });
  });

  it("devuelve null en vez de adivinar cuando el texto no se entiende", () => {
    expect(partesDeFecha("no-es-una-fecha")).toBeNull();
    expect(partesDeFecha("")).toBeNull();
    expect(partesDeFecha("   ")).toBeNull();
    expect(partesDeFecha(null)).toBeNull();
    expect(partesDeFecha(undefined)).toBeNull();
  });
});

describe("calendarioEcuador", () => {
  /** 2026-03-01T05:00:00Z son las 00:00 del 1 de marzo en Ecuador. */
  const MEDIANOCHE_ECUADOR = Date.parse("2026-03-01T05:00:00.000Z");

  it("se queda en el mismo dia mientras Ecuador aun no ha cambiado de dia", () => {
    // 2026-03-01T04:59:59Z todavia son las 23:59:59 del 28 en Ecuador.
    expect(calendarioEcuador(Date.parse("2026-03-01T04:59:59.000Z"))).toEqual({
      anio: 2026,
      mes: 2,
      dia: 28,
    });
  });

  it("cambia de dia en cuanto Ecuador pasa la medianoche", () => {
    expect(calendarioEcuador(MEDIANOCHE_ECUADOR)).toEqual({
      anio: 2026,
      mes: 3,
      dia: 1,
    });
  });

  it("va cinco horas atras, no cinco adelante", () => {
    // Un error clasico seria restar en vez de sumar al offset.
    expect(calendarioEcuador(Date.parse("2026-03-01T00:30:00.000Z"))).toEqual({
      anio: 2026,
      mes: 2,
      dia: 28,
    });
  });

  it("da el mismo resultado que la hora de Quito, en cualquier dia del año", () => {
    for (const dia of [1, 60, 200, 320]) {
      const instante = Date.parse("2026-01-01T00:00:00.000Z") + dia * 86400000;
      // en-CA formatea como 2026-03-01, que se separa sin adivinar el orden.
      const esperado = new Date(instante)
        .toLocaleString("en-CA", {
          timeZone: "America/Guayaquil",
          year: "numeric",
          month: "numeric",
          day: "numeric",
        })
        .split("-")
        .map(Number);
      expect(calendarioEcuador(instante)).toEqual({
        anio: esperado[0],
        mes: esperado[1],
        dia: esperado[2],
      });
    }
  });
});
