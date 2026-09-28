import { describe, it, expect, beforeAll } from "vitest";
import { env } from "cloudflare:test";
import { verificarHorarioEvento } from "../index";

const db = env.DB;

/**
 * Un evento de septiembre de 2026 que abre a las 08:00 y cierra a las 20:00,
 * en hora de Ecuador. Se usa en toda la tabla.
 */
const EVENTO_CON_HORARIO = 1;
const EVENTO_SIN_HORARIO = 2;

beforeAll(async () => {
  await db
    .prepare(
      `CREATE TABLE IF NOT EXISTS eventos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        organizador_id INTEGER NOT NULL,
        nombre TEXT NOT NULL,
        fecha_inicio TEXT NOT NULL,
        fecha_fin TEXT NOT NULL
      )`
    )
    .run();

  await db
    .prepare(
      `INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin)
       VALUES (?, ?, ?, ?)`
    )
    .bind(1, "Festival", "2026-09-01 08:00:00", "2026-09-30 20:00:00")
    .run();

  // Un evento cuyas fechas no se pueden leer, para ver que no se bloquea a
  // nadie por un dato que el sistema no entiende.
  await db
    .prepare(
      `INSERT INTO eventos (organizador_id, nombre, fecha_inicio, fecha_fin)
       VALUES (?, ?, ?, ?)`
    )
    .bind(1, "Evento Roto", "no es fecha", "tampoco")
    .run();
});

/**
 * Cada fila es una compra y lo que tiene que pasar.
 *
 * `esperado` es si la compra se acepta. La columna `porque` explica el motivo en
 * palabras, que es la parte que hace falta leer cuando algo falla.
 */
const CASOS: Array<{
  fecha: string | null;
  esperado: boolean;
  porque: string;
}> = [
  // Formato del OCR: DD/MM/YYYY, solo dia.
  {
    fecha: "15/09/2026",
    esperado: true,
    porque: "DD/MM/YYYY a mitad de mes, dentro del evento",
  },
  {
    fecha: "01/09/2026",
    esperado: true,
    porque: "DD/MM/YYYY el primer dia, que es el dia que abre",
  },
  {
    fecha: "30/09/2026",
    esperado: true,
    porque: "DD/MM/YYYY el ultimo dia, que es el dia que cierra",
  },
  {
    fecha: "15/08/2026",
    esperado: false,
    porque: "DD/MM/YYYY de antes del evento",
  },
  {
    fecha: "05/10/2026",
    esperado: false,
    porque: "DD/MM/YYYY de despues del evento",
  },

  // Formato de la compra declarada: D-M-YY, solo dia.
  {
    fecha: "1-9-26",
    esperado: true,
    porque: "D-M-YY dentro, y los dos digitos son 2026",
  },
  {
    fecha: "1-8-26",
    esperado: false,
    porque: "D-M-YY de antes del evento",
  },
  {
    fecha: "5-10-26",
    esperado: false,
    porque: "D-M-YY de despues del evento",
  },

  // Formato del SRI: ISO con offset, con hora exacta.
  {
    fecha: "2026-09-15T10:00:00-05:00",
    esperado: true,
    porque: "ISO con offset dentro del horario",
  },
  // Estas dos son las que separan comparar por dia de comparar por instante.
  // El 15 de septiembre a las 07:00 esta dentro del evento de cualquier
  // manera: solo importan las horas del primer y del ultimo dia.
  {
    fecha: "2026-09-01T09:00:00-05:00",
    esperado: true,
    porque: "ISO la manana del primer dia, con el evento ya abierto",
  },
  {
    fecha: "2026-09-01T07:00:00-05:00",
    esperado: false,
    porque:
      "ISO antes de que abra el primer dia. Con solo el dia pasaria, porque el 1 de septiembre esta dentro",
  },
  {
    fecha: "2026-09-01T08:00:00-05:00",
    esperado: true,
    porque: "ISO el instante exacto en que abre",
  },
  {
    fecha: "2026-09-30T21:00:00-05:00",
    esperado: false,
    porque:
      "ISO una hora despues de que cierre. El dia es el ultimo, pero la hora no",
  },
  {
    fecha: "2026-09-30T19:00:00-05:00",
    esperado: true,
    porque: "ISO la ultima hora que sigue abierta",
  },
  {
    fecha: "2026-10-01T10:00:00-05:00",
    esperado: false,
    porque: "ISO de despues del evento",
  },
  {
    fecha: "2026-08-31T23:00:00-05:00",
    esperado: false,
    porque: "ISO de antes del evento",
  },
  {
    fecha: "2026-09-15T15:00:00Z",
    esperado: true,
    porque: "ISO en UTC que es la misma hora local dentro del horario",
  },

  // Fechas que no se pueden leer: no se bloquea, pero a proposito.
  {
    fecha: "no es una fecha",
    esperado: true,
    porque: "no se puede leer, y bloquear por eso seria rechazar una compra buena",
  },
  {
    fecha: "",
    esperado: true,
    porque: "vacia",
  },
  {
    fecha: "31/02/2026",
    esperado: true,
    porque: "el 31 de febrero no existe",
  },
  {
    fecha: "2026-09-15 25:00:00",
    esperado: true,
    porque: "dice que trae hora, pero las 25:00 no existen",
  },
];

describe("verificarHorarioEvento", () => {
  it.each(CASOS)(
    "fecha $fecha -> $esperado ($porque)",
    async ({ fecha, esperado }) => {
      const resultado = await verificarHorarioEvento(db, {
        eventoId: EVENTO_CON_HORARIO,
        fechaFactura: fecha,
      });

      expect(resultado.valido).toBe(esperado);
      if (!esperado) {
        // Cuando rechaza, tiene que decir por que y repetir la fecha, que es
        // lo que lee la persona que la registro.
        expect(resultado.motivo).toContain("fuera del rango");
        expect(resultado.motivo).toContain(fecha!);
      }
    }
  );

  it("acepta la compra si no se envio evento", async () => {
    const resultado = await verificarHorarioEvento(db, {
      eventoId: null,
      fechaFactura: "15/08/2026",
    });

    expect(resultado.valido).toBe(true);
  });

  it("acepta la compra si no se envio fecha", async () => {
    const resultado = await verificarHorarioEvento(db, {
      eventoId: EVENTO_CON_HORARIO,
      fechaFactura: null,
    });

    expect(resultado.valido).toBe(true);
  });

  it("acepta la compra si el evento no tiene horario legible", async () => {
    // Sin ventana conocida no se puede afirmar que la compra este fuera, asi
    // que no se bloquea a nadie.
    const resultado = await verificarHorarioEvento(db, {
      eventoId: EVENTO_SIN_HORARIO,
      fechaFactura: "15/09/2026",
    });

    expect(resultado.valido).toBe(true);
  });

  it("rechaza si el evento no existe", async () => {
    const resultado = await verificarHorarioEvento(db, {
      eventoId: 9999,
      fechaFactura: "15/09/2026",
    });

    expect(resultado.valido).toBe(false);
    expect(resultado.motivo).toContain("no existe");
  });

  it("no confunde el dia con el mes en las fechas cortas", async () => {
    // Esta es la trampa que mas dano hacia. new Date() lee 01/09/2026 como el 9
    // de enero, porque asume el formato americano de mes/dia, no el nuestro de
    // dia/mes. Una compra legitima del 1 de septiembre acababa rechazada por
    // estar "antes" del evento. Lo mismo pasaba con 1-9-26.
    const septiembre = await verificarHorarioEvento(db, {
      eventoId: EVENTO_CON_HORARIO,
      fechaFactura: "01/09/2026",
    });
    const septiembreCorto = await verificarHorarioEvento(db, {
      eventoId: EVENTO_CON_HORARIO,
      fechaFactura: "1-9-26",
    });

    expect(septiembre.valido).toBe(true);
    expect(septiembreCorto.valido).toBe(true);
  });

  it("rechaza una compra de antes del evento aunque la fecha solo tenga dia", async () => {
    // Esta es la prueba que antes no podia pasar. Con new Date(), 15/08/2026
    // daba NaN, la comparacion con NaN es falsa, y la compra se aceptaba.
    const resultado = await verificarHorarioEvento(db, {
      eventoId: EVENTO_CON_HORARIO,
      fechaFactura: "15/08/2026",
    });

    expect(resultado.valido).toBe(false);
  });
});
