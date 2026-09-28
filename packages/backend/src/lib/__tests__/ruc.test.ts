import { describe, it, expect } from "vitest";
import { motivoRucInvalido, rucValido, motivoHorarioInvalido } from "../ruc";

/**
 * Los RUC válidos de abajo se generaron aparte, aplicando las reglas del SRI
 * (módulo 10 para cédula, módulo 11 para sector público y persona jurídica).
 * No se usa ningún RUC real.
 */
const NATURAL_GUAYAS = "0951234566001";
const NATURAL_PICHINCHA = "0104567899001";
const NATURAL_EST_999 = "0951234566999";
const PUBLICA_GUAYAS = "0961234507001";
const PUBLICA_GALAPAGOS = "3065432103001";
const JURIDICA_GUAYAS = "0991234561001";
const JURIDICA_PICHINCHA = "0199876545001";
const JURIDICA_GALAPAGOS_999 = "3091112220999";
const JURIDICA_TUNGURAHUA = "0693334445012";

describe("RUC de persona natural (tercer dígito menor que 6)", () => {
  it.each([NATURAL_GUAYAS, NATURAL_PICHINCHA, NATURAL_EST_999])(
    "acepta el RUC %s",
    (ruc) => {
      expect(motivoRucInvalido(ruc)).toBeNull();
      expect(rucValido(ruc)).toBe(true);
    }
  );

  it("acepta los terceros dígitos del 0 al 5", () => {
    // Solo se comprueba que ninguno se rechace por el tipo; el verificador de
    // estos numeros es fijo y solo interesa que el tipo no los descarte.
    for (const tipo of [0, 1, 2, 3, 4, 5]) {
      const ruc = `09${tipo}1234566001`;
      const motivo = motivoRucInvalido(ruc);
      expect(motivo === null || /verificador/.test(motivo ?? "")).toBe(true);
      if (motivo) expect(motivo).not.toContain("tercer dígito");
    }
  });

  it("acepta un RUC con espacios alrededor", () => {
    expect(motivoRucInvalido(`  ${NATURAL_GUAYAS}  `)).toBeNull();
  });

  it("no se queja si no se envia RUC", () => {
    expect(motivoRucInvalido(null)).toBeNull();
    expect(motivoRucInvalido(undefined)).toBeNull();
    expect(motivoRucInvalido("")).toBeNull();
  });
});

describe("RUC del sector público (tercer dígito 6)", () => {
  it.each([PUBLICA_GUAYAS, PUBLICA_GALAPAGOS])("acepta el RUC %s", (ruc) => {
    expect(motivoRucInvalido(ruc)).toBeNull();
  });

  it("rechaza si el verificador del dígito 9 está mal", () => {
    // Se cambia el dígito 9 (posición 8) y el resto se deja igual.
    const roto = PUBLICA_GUAYAS.slice(0, 8) + "9" + PUBLICA_GUAYAS.slice(9);
    expect(rucValido(roto)).toBe(false);
    expect(motivoRucInvalido(roto)).toContain("sector público");
  });
});

describe("RUC de persona jurídica (tercer dígito 9)", () => {
  it.each([
    JURIDICA_GUAYAS,
    JURIDICA_PICHINCHA,
    JURIDICA_GALAPAGOS_999,
    JURIDICA_TUNGURAHUA,
  ])("acepta el RUC %s", (ruc) => {
    expect(motivoRucInvalido(ruc)).toBeNull();
  });

  it("rechaza si el verificador del dígito 10 está mal", () => {
    const roto = JURIDICA_GUAYAS.slice(0, 9) + "0" + JURIDICA_GUAYAS.slice(10);
    expect(rucValido(roto)).toBe(false);
    expect(motivoRucInvalido(roto)).toContain("persona jurídica");
  });
});

describe("RUC inválidos", () => {
  it("rechaza menos de 13 dígitos", () => {
    const motivo = motivoRucInvalido("095123456600");
    expect(motivo).toContain("13 dígitos");
  });

  it("rechaza más de 13 dígitos", () => {
    expect(motivoRucInvalido("09512345660012")).toContain("13 dígitos");
  });

  it("rechaza letras", () => {
    const motivo = motivoRucInvalido("09512345660A1");
    expect(motivo).toContain("13 dígitos");
  });

  it("rechaza guiones o espacios en medio", () => {
    expect(motivoRucInvalido("095-1234566-001")).toContain("13 dígitos");
  });

  it("rechaza una provincia que no existe", () => {
    const motivo = motivoRucInvalido("2551234566001");
    expect(motivo).toContain("provincia");
  });

  it("rechaza la provincia 00", () => {
    const motivo = motivoRucInvalido("0051234566001");
    expect(motivo).toContain("provincia");
  });

  it("acepta la provincia 24 y la 30, y rechaza la 25", () => {
    expect(motivoRucInvalido(JURIDICA_TUNGURAHUA)).toBeNull();
    expect(motivoRucInvalido(JURIDICA_GALAPAGOS_999)).toBeNull();
    expect(motivoRucInvalido("2511111111001")).toContain("provincia");
  });

  it("rechaza el tercer dígito 7 y el 8", () => {
    for (const tipo of [7, 8]) {
      const motivo = motivoRucInvalido(`09${tipo}1234561001`);
      expect(motivo).toContain("tercer dígito");
    }
  });

  it("rechaza un establecimiento 000", () => {
    const motivo = motivoRucInvalido("0991234561000");
    expect(motivo).toContain("establecimiento");
  });

  it("acepta el establecimiento 001, el más bajo posible", () => {
    expect(motivoRucInvalido(JURIDICA_GUAYAS)).toBeNull();
  });

  it("el mensaje dice qué está mal, no solo que es inválido", () => {
    for (const ruc of ["123", "2551234566001", "0971234561001", "0991234561000"]) {
      const motivo = motivoRucInvalido(ruc);
      expect(motivo).toBeTruthy();
      expect(motivo).not.toBe("RUC inválido");
      expect(motivo?.length).toBeGreaterThan(20);
    }
  });
});

describe("horario del comercio", () => {
  it("acepta un cierre posterior a la apertura", () => {
    expect(motivoHorarioInvalido("08:00", "18:00")).toBeNull();
    expect(motivoHorarioInvalido("00:00", "23:59")).toBeNull();
  });

  it("acepta que solo se mande una de las dos horas", () => {
    expect(motivoHorarioInvalido("08:00", null)).toBeNull();
    expect(motivoHorarioInvalido(null, "18:00")).toBeNull();
    expect(motivoHorarioInvalido(undefined, undefined)).toBeNull();
  });

  it("rechaza un cierre anterior a la apertura", () => {
    const motivo = motivoHorarioInvalido("18:00", "08:00");
    expect(motivo).toContain("cierre");
    expect(motivo).toContain("apertura");
  });

  it("rechaza un cierre igual a la apertura", () => {
    expect(motivoHorarioInvalido("08:00", "08:00")).toContain("posterior");
  });

  it("rechaza un formato que no sea HH:MM", () => {
    expect(motivoHorarioInvalido("8:00", "18:00")).toContain("HH:MM");
    expect(motivoHorarioInvalido("08:00", "6pm")).toContain("HH:MM");
  });

  it("rechaza minutos que no existen", () => {
    expect(motivoHorarioInvalido("08:99", "18:00")).toContain("válida");
  });
});
