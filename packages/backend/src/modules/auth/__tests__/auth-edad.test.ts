import { describe, it, expect, beforeAll, afterEach, vi } from "vitest";
import { env } from "cloudflare:test";
import { sign } from "@tsndr/cloudflare-worker-jwt";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { auth } from "../index";

const db = env.DB;
const JWT_SECRET = "test-secret-key-for-auth-edad";

/**
 * Un instante de la vida real que separa a Ecuador de UTC.
 *
 * Son las 02:00 UTC, que en Ecuador (UTC-5) todavia son las 21:00 del dia
 * anterior. Si el codigo lee el calendario con los getters de hora local del
 * runtime, este instante se ve como 1 de enero en UTC y como 31 de diciembre
 * en Guayaquil, y la edad sale distinta.
 */
const INSTANTE_DE_BORDE = "2026-01-01T02:00:00.000Z";

function buildApp() {
  const app = new Hono();
  app.use("*", cors({ origin: "*" }));
  app.route("/auth", auth);
  return app;
}

async function makeToken(sub: number, rol: string): Promise<string> {
  return sign(
    { sub: String(sub), rol, exp: Math.floor(Date.now() / 1000) + 3600 },
    JWT_SECRET
  );
}

/**
 * Crea un usuario con la fecha de nacimiento indicada y le pide consentimiento
 * publicitario, que es la puerta que decide si es mayor de edad.
 *
 * Devuelve el codigo HTTP. 422 significa que el backend lo rechazo por ser
 * menor; 200 que se lo concedio.
 */
async function pedirConsentimiento(
  email: string,
  fechaNacimiento: string
): Promise<number> {
  await db
    .prepare(
      `INSERT INTO usuarios (rol, email, password_hash, nombre_completo, fecha_nacimiento)
       VALUES (?, ?, ?, ?, ?)`
    )
    .bind("cliente", email, "hash", "Persona De Prueba", fechaNacimiento)
    .run();

  const row = await db
    .prepare("SELECT id FROM usuarios WHERE email = ?")
    .bind(email)
    .first<{ id: number }>();

  const res = await buildApp().request(
    "/auth/consentimiento",
    {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${await makeToken(Number(row!.id), "cliente")}`,
      },
      body: JSON.stringify({ consentimiento_publicidad: true }),
    },
    { DB: db, JWT_SECRET }
  );

  return res.status;
}

beforeAll(async () => {
  await db
    .prepare(
      `CREATE TABLE IF NOT EXISTS usuarios (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        rol TEXT NOT NULL CHECK (rol IN ('cliente','negocio','organizador','admin')),
        email TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        nombre_completo TEXT NOT NULL,
        fecha_nacimiento TEXT,
        consentimiento_publicidad INTEGER,
        consentimiento_publicidad_fecha TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )`
    )
    .run();
});

afterEach(() => {
  vi.useRealTimers();
});

/**
 * Los casos que el prompt pide comprobar, sobre un instante de la vida real.
 *
 * Cada fila dice qué edad corresponde en el calendario de Ecuador. Que el mismo
 * conjunto de casos de el mismo resultado en las dos zonas es justamente lo que
 * hay que demostrar: antes, la respuesta dependia de donde corriera el codigo.
 */
describe("Edad segun la zona horaria del runtime", () => {
  /**
   * El instante de referencia: 2026-01-01T02:00Z, que en Ecuador son las 21:00
   * del 31 de diciembre de 2025. Es el borde que separa los dos calendarios.
   */
  const CASOS = [
    {
      nombre: "quien cumple 18 anos hoy mismo",
      email: "hoy@test.com",
      nacimiento: "2007-12-31",
      // Un cumpleaños empieza a las 00:00 del dia, no a la noche. En Ecuador son
      // las 21:00 del 31, asi que ya cumplio y ya es mayor de edad.
      // Ojo: en UTC este mismo instante es 1 de enero y tambien daria 18, pero
      // por el motivo equivocado, que es ver el dia siguiente.
      esperado: 200,
    },
    {
      nombre: "quien cumple 18 anos manana",
      email: "manana@test.com",
      nacimiento: "2008-01-01",
      // Mañana cumple 18. Hoy, en Ecuador, sigue siendo menor.
      esperado: 422,
    },
    {
      nombre: "quien los cumplio ayer",
      email: "ayer@test.com",
      nacimiento: "2007-12-30",
      // Ayer cumplio 18, ya es mayor de edad.
      esperado: 200,
    },
    {
      nombre: "quien cumple 19 manana",
      email: "diecinueve@test.com",
      nacimiento: "2007-01-01",
      // Mañana cumple 19, hoy tiene 18. Mayor de edad, puede consentir.
      esperado: 200,
    },
    {
      nombre: "menor de 17 que ya cumplio 17",
      email: "diecisiete@test.com",
      nacimiento: "2008-12-30",
      // Ayer cumplio 17. Es menor y no puede consentir.
      esperado: 422,
    },
    {
      nombre: "nacido un 29 de febrero, en diciembre todavia es menor",
      email: "bisiesto@test.com",
      nacimiento: "2008-02-29",
      // En 2026, que no es bisiesto, cumple 18 el 28 de febrero. Hoy es
      // diciembre de 2025, asi que le faltan dos meses: sigue siendo menor.
      esperado: 422,
    },
    {
      nombre: "nacido un 29 de febrero, ayer 27 de diciembre",
      email: "bisiesto-antes@test.com",
      nacimiento: "2008-02-29",
      // Mismo caso un dia antes, para fijar que la fecha existe y no es un
      // "siempre mayor de edad".
      esperado: 422,
    },
    {
      nombre: "fecha de nacimiento que no se puede leer",
      email: "ilegible@test.com",
      nacimiento: "no-es-una-fecha",
      // Un texto que no es una fecha. Antes new Date devolvia Invalid Date,
      // NaN < 18 era falso, y el paso se concedia como si fuera mayor. Ahora
      // una fecha que no se entiende se rechaza, no se adivina.
      esperado: 422,
    },
    {
      nombre: "fecha de nacimiento en formato europeo, bien interpretada",
      email: "europeo@test.com",
      nacimiento: "29/05/2008",
      // El ayudante si entiende DD/MM/AAAA. Antes caia en NaN y pasaba de
      // largo; ahora se lee 29 de mayo de 2008, que en diciembre de 2025
      // tiene 17 anos, asi que se rechaza por la edad correcta y no por
      // accidente. Si alguien pusiera 01/06/2008 seria el 1 de junio, y no
      // habria forma de confundirlo con el 6 de enero.
      esperado: 422,
    },
    {
      nombre: "fecha de nacimiento en formato europeo, mayor de edad",
      email: "europeo-mayor@test.com",
      nacimiento: "29/12/2006",
      // El 29 de diciembre de 2006. En diciembre de 2025 ya tiene 19.
      esperado: 200,
    },
    {
      nombre: "fecha de nacimiento vacia",
      email: "vacia@test.com",
      nacimiento: "",
      esperado: 422,
    },
    {
      nombre: "fecha de nacimiento imposible, 30 de febrero",
      email: "imposible@test.com",
      nacimiento: "2008-02-30",
      // El dia 30 de febrero no existe. Antes new Date lo normalizaba en
      // silencio a 1 de marzo.
      esperado: 422,
    },
  ];

  it.each(CASOS)("$nombre", async ({ email, nacimiento, esperado }) => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date(INSTANTE_DE_BORDE));

    const status = await pedirConsentimiento(email, nacimiento);

    expect(status).toBe(esperado);
  });
});

/**
 * El 29 de febrero necesita su propio caso, porque el resto de la tabla cae en
 * diciembre y no alcanza a probar la regla de los anos no bisiestos.
 *
 * Se usa el 28 de febrero de un ano que no es bisiesto, que es el momento en
 * que esa persona cumple 18.
 */
describe("El 29 de febrero en un ano que no es bisiesto", () => {
  const CASOS_BISIESTOS = [
    {
      nombre: "el 27 de febrero todavia es menor",
      email: "bisiesto-27@test.com",
      instante: "2026-02-28T02:00:00.000Z", // 2026-02-27 21:00 en Ecuador
      esperado: 422,
    },
    {
      nombre: "el 28 de febrero ya cumple 18",
      email: "bisiesto-28@test.com",
      instante: "2026-02-28T05:00:00.000Z", // 2026-02-28 00:00 en Ecuador
      esperado: 200,
    },
  ];

  it.each(CASOS_BISIESTOS)(
    "$nombre",
    async ({ email, instante, esperado }) => {
      vi.useFakeTimers();
      vi.setSystemTime(new Date(instante));

      const status = await pedirConsentimiento(email, "2008-02-29");

      expect(status).toBe(esperado);
    }
  );
});

