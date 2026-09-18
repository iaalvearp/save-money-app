import { describe, it, expect } from "vitest";
import { validarChecksum } from "../index";

function computeCheckDigit(digits: number[]): number {
  let sum = 0;
  let multiplier = 2;
  for (let i = digits.length - 1; i >= 0; i--) {
    sum += digits[i] * multiplier;
    multiplier++;
    if (multiplier > 7) {
      multiplier = 2;
    }
  }
  const remainder = sum % 11;
  return remainder === 0 ? 0 : 11 - remainder;
}

function buildValidClave(): string {
  const base = "123456789012345678901234567890123456789012345678";
  const digits = base.split("").map(Number);
  const checkDigit = computeCheckDigit(digits);
  return base.slice(0, 48) + String(checkDigit);
}

describe("validarChecksum", () => {
  it("acepta una clave con checksum válido", () => {
    const clave = buildValidClave();
    expect(validarChecksum(clave)).toBe(true);
  });

  it("rechaza una clave con checksum inválido", () => {
    const clave = buildValidClave();
    const lastDigit = parseInt(clave[48], 10);
    const wrongDigit = (lastDigit + 1) % 10;
    const wrongClave = clave.slice(0, 48) + String(wrongDigit);
    expect(validarChecksum(wrongClave)).toBe(false);
  });

  it("rechaza una clave con longitud incorrecta", () => {
    expect(validarChecksum("1234567890")).toBe(false);
    expect(validarChecksum("12345678901234567890123456789012345678901234567")).toBe(false);
  });

  it("rechaza una clave con caracteres no numéricos", () => {
    const clave = buildValidClave();
    const badClave = "a" + clave.slice(1);
    expect(validarChecksum(badClave)).toBe(false);
  });
});
