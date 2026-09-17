const SRI_AUTORIZACION_URL =
  "https://cel.sri.gob.ec/comprobantes-electronicos-ws/AutorizacionComprobantesOffline";
const SRI_AUTORIZACION_NS = "http://ec.gob.sri.ws.autorizacion";
const SRI_TIMEOUT_MS = 15_000;

export interface SRIResultado {
  estado:
    | "autorizado"
    | "no_autorizado"
    | "rechazada"
    | "servicio_no_disponible";
  ruc_emisor: string | null;
  fecha_autorizacion: string | null;
  monto: number | null;
  nombre_comprador: string | null;
  mensaje_sri: string | null;
}

export function validarChecksum(clave: string): boolean {
  if (clave.length !== 49 || !/^\d{49}$/.test(clave)) {
    return false;
  }

  const digits = clave.split("").map(Number);
  const checkDigit = digits.pop()!;

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
  const expected = remainder === 0 ? 0 : 11 - remainder;

  return checkDigit === expected;
}

function buildSoapEnvelope(claveAcceso: string): string {
  return `<?xml version="1.0" encoding="UTF-8"?>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ec="${SRI_AUTORIZACION_NS}">
  <soapenv:Header/>
  <soapenv:Body>
    <ec:autorizacionComprobante>
      <claveAccesoComprobante>${claveAcceso}</claveAccesoComprobante>
    </ec:autorizacionComprobante>
  </soapenv:Body>
</soapenv:Envelope>`;
}

function getTextContent(el: Element, tagName: string): string | null {
  const child = el.getElementsByTagName(tagName)[0];
  return child?.textContent?.trim() || null;
}

function extractDataFromComprobanteXml(xmlStr: string): {
  monto: number | null;
  nombre_comprador: string | null;
  ruc_emisor: string | null;
} {
  try {
    const parser = new DOMParser();
    const doc = parser.parseFromString(xmlStr, "text/xml");

    const parseError = doc.querySelector("parsererror");
    if (parseError) {
      return { monto: null, nombre_comprador: null, ruc_emisor: null };
    }

    const infoTributaria = doc.getElementsByTagName("infoTributaria")[0];
    let rucEmisor: string | null = null;
    if (infoTributaria) {
      rucEmisor = getTextContent(infoTributaria, "ruc") || null;
    }

    const infoFactura = doc.getElementsByTagName("infoFactura")[0];
    let monto: number | null = null;
    let nombreComprador: string | null = null;

    if (infoFactura) {
      const importeTotalStr = getTextContent(infoFactura, "importeTotal");
      if (importeTotalStr) {
        const parsed = parseFloat(importeTotalStr);
        if (!isNaN(parsed)) {
          monto = parsed;
        }
      }

      const razonSocial = getTextContent(infoFactura, "razonSocialComprador");
      const identificacion = getTextContent(
        infoFactura,
        "identificacionComprador"
      );

      if (razonSocial && razonSocial.toUpperCase() !== "CONSUMIDOR FINAL") {
        nombreComprador = razonSocial;
      } else if (
        identificacion &&
        identificacion.toUpperCase() !== "CONSUMIDOR FINAL" &&
        identificacion !== "9999999999999"
      ) {
        nombreComprador = identificacion;
      }
    }

    return { monto, nombre_comprador: nombreComprador, ruc_emisor: rucEmisor };
  } catch {
    return { monto: null, nombre_comprador: null, ruc_emisor: null };
  }
}

function parseAutorizacionResponse(xmlText: string): SRIResultado {
  const parser = new DOMParser();
  const doc = parser.parseFromString(xmlText, "text/xml");

  const faultEl = doc.querySelector("Fault");
  if (faultEl) {
    return {
      estado: "servicio_no_disponible",
      ruc_emisor: null,
      fecha_autorizacion: null,
      monto: null,
      nombre_comprador: null,
      mensaje_sri: "Fault SOAP del SRI",
    };
  }

  const autorizacion = doc.getElementsByTagName("autorizacion")[0];
  if (!autorizacion) {
    return {
      estado: "servicio_no_disponible",
      ruc_emisor: null,
      fecha_autorizacion: null,
      monto: null,
      nombre_comprador: null,
      mensaje_sri: "Respuesta del SRI sin elemento autorizacion",
    };
  }

  const estado = getTextContent(autorizacion, "estado");
  const fechaAutorizacion = getTextContent(autorizacion, "fechaAutorizacion");
  const comprobanteXml = getTextContent(autorizacion, "comprobante");

  const mensajes = autorizacion.getElementsByTagName("mensaje");
  let primerMensaje: string | null = null;
  if (mensajes.length > 0) {
    primerMensaje = getTextContent(mensajes[0], "mensaje");
  }

  let estadoMapped: SRIResultado["estado"];
  if (estado?.toUpperCase() === "AUTORIZADO") {
    estadoMapped = "autorizado";
  } else if (estado?.toUpperCase() === "NO AUTORIZADO") {
    estadoMapped = "no_autorizado";
  } else if (estado?.toUpperCase() === "RECHAZADO") {
    estadoMapped = "rechazada";
  } else {
    estadoMapped = "no_autorizado";
  }

  let rucEmisor: string | null = null;
  let monto: number | null = null;
  let nombreComprador: string | null = null;

  if (estadoMapped === "autorizado" && comprobanteXml) {
    const decoded = comprobanteXml
      .replace(/&lt;/g, "<")
      .replace(/&gt;/g, ">")
      .replace(/&amp;/g, "&")
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'");
    const extracted = extractDataFromComprobanteXml(decoded);
    rucEmisor = extracted.ruc_emisor;
    monto = extracted.monto;
    nombreComprador = extracted.nombre_comprador;
  }

  return {
    estado: estadoMapped,
    ruc_emisor: rucEmisor,
    fecha_autorizacion: fechaAutorizacion,
    monto,
    nombre_comprador: nombreComprador,
    mensaje_sri: primerMensaje,
  };
}

export async function consultarSRI(clave: string): Promise<SRIResultado> {
  const envelope = buildSoapEnvelope(clave);

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), SRI_TIMEOUT_MS);

  try {
    const response = await fetch(SRI_AUTORIZACION_URL, {
      method: "POST",
      headers: {
        "Content-Type": "text/xml; charset=UTF-8",
        SOAPAction: "",
      },
      body: envelope,
      signal: controller.signal,
    });

    clearTimeout(timeoutId);

    if (!response.ok) {
      return {
        estado: "servicio_no_disponible",
        ruc_emisor: null,
        fecha_autorizacion: null,
        monto: null,
        nombre_comprador: null,
        mensaje_sri: `HTTP ${response.status} del SRI`,
      };
    }

    const xmlText = await response.text();
    return parseAutorizacionResponse(xmlText);
  } catch (err) {
    clearTimeout(timeoutId);
    const msg =
      err instanceof Error && err.name === "AbortError"
        ? "Timeout del SRI (>15s)"
        : `Error de red: ${err instanceof Error ? err.message : String(err)}`;
    return {
      estado: "servicio_no_disponible",
      ruc_emisor: null,
      fecha_autorizacion: null,
      monto: null,
      nombre_comprador: null,
      mensaje_sri: msg,
    };
  }
}
