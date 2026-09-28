import { describe, it, expect } from "vitest";
import {
  instanteDeCompra,
  diaComoCalendario,
  esFechaLegible,
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
