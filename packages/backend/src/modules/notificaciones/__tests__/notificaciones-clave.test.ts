import { describe, it, expect, beforeAll, afterEach } from "vitest";
import { enviarNotificacion } from "../index";
import {
  generarClavePrivadaBase64DePrueba,
  interceptarFcm,
} from "../../../test-utils/fcm";

const FCM_CLIENT_EMAIL =
  "firebase-adminsdk-pruebas@save-money-pruebas.iam.gserviceaccount.com";

let lineas: string[];
let fcm: ReturnType<typeof interceptarFcm>;

beforeAll(async () => {
  lineas = await generarClavePrivadaBase64DePrueba();
});

afterEach(() => {
  fcm?.restaurar();
});

/**
 * La clave privada se pega en Cloudflare a mano y segun como se copie puede
 * llegar con los saltos de linea reales, como la sequencia de dos caracteres
 * "\n", entre comillas o con finales "\r\n". Todas esas formas deben servir,
 * porque el mismo valor pegado de otra manera no puede romper el envio.
 */
describe("leer la clave privada de Firebase", () => {
  it("acepta la clave con saltos de linea reales", async () => {
    const clave = `-----BEGIN PRIVATE KEY-----\n${lineas.join("\n")}\n-----END PRIVATE KEY-----\n`;

    await enviarConClave(clave);

    expect(fcm.envios).toHaveLength(1);
  });

  it('acepta la clave con "\\n" literal en vez de saltos de linea', async () => {
    const clave = `-----BEGIN PRIVATE KEY-----\\n${lineas.join("\\n")}\\n-----END PRIVATE KEY-----\\n`;

    await enviarConClave(clave);

    expect(fcm.envios).toHaveLength(1);
  });

  it('acepta la clave con "\\r\\n" literal', async () => {
    const clave = `-----BEGIN PRIVATE KEY-----\\r\\n${lineas.join("\\r\\n")}\\r\\n-----END PRIVATE KEY-----\\r\\n`;

    await enviarConClave(clave);

    expect(fcm.envios).toHaveLength(1);
  });

  it("acepta la clave con finales CRLF reales", async () => {
    const clave = `-----BEGIN PRIVATE KEY-----\r\n${lineas.join("\r\n")}\r\n-----END PRIVATE KEY-----\r\n`;

    await enviarConClave(clave);

    expect(fcm.envios).toHaveLength(1);
  });

  it("acepta la clave envuelta en comillas dobles", async () => {
    const clave = `"-----BEGIN PRIVATE KEY-----\\n${lineas.join("\\n")}\\n-----END PRIVATE KEY-----\\n"`;

    await enviarConClave(clave);

    expect(fcm.envios).toHaveLength(1);
  });

  it("acepta la clave envuelta en comillas simples", async () => {
    const clave = `'-----BEGIN PRIVATE KEY-----\n${lineas.join("\n")}\n-----END PRIVATE KEY-----\n'`;

    await enviarConClave(clave);

    expect(fcm.envios).toHaveLength(1);
  });

  it("acepta la clave con espacios y tabuladores de sobra", async () => {
    const clave = `  -----BEGIN PRIVATE KEY-----\n   ${lineas.join("  \n")}\t\n  -----END PRIVATE KEY-----\n  `;

    await enviarConClave(clave);

    expect(fcm.envios).toHaveLength(1);
  });

  it("acepta la clave sin las lineas BEGIN y END", async () => {
    const clave = lineas.join("\n");

    await enviarConClave(clave);

    expect(fcm.envios).toHaveLength(1);
  });
});

describe("cuando la clave no se puede leer", () => {
  it("falla con un mensaje que dice que revisar FCM_PRIVATE_KEY", async () => {
    fcm = interceptarFcm();

    await expect(enviarConClave("esto no es una clave")).rejects.toThrow(
      /FCM_PRIVATE_KEY/
    );
  });

  it("falla con un mensaje claro si la clave esta vacia", async () => {
    fcm = interceptarFcm();

    await expect(
      enviarConClave("-----BEGIN PRIVATE KEY-----\\n-----END PRIVATE KEY-----")
    ).rejects.toThrow(/FCM_PRIVATE_KEY/);
  });

  it("falla con un mensaje claro si la clave son solo espacios", async () => {
    fcm = interceptarFcm();

    await expect(enviarConClave("    \n\t  ")).rejects.toThrow(/FCM_PRIVATE_KEY/);
  });
});

/** Intenta enviar una notificacion con la clave indicada y deja FCM interceptado. */
async function enviarConClave(clave: string): Promise<void> {
  fcm = interceptarFcm();
  const c = { env: { FCM_CLIENT_EMAIL, FCM_PRIVATE_KEY: clave } } as never;
  await enviarNotificacion(c, "token-de-prueba", "Título", "Cuerpo");
}
