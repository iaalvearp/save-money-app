const SRI_WSDL_URL =
  "https://cel.sri.gob.ec/comprobantes-electronicos-ws/ConsultaComprobante";
const SRI_NS = "http://ec.gob.sri.ws.consultas";
const SRI_TIMEOUT_MS = 10_000;

export interface SRIResultado {
  estado: "autorizado" | "no_autorizado" | "rechazada" | "servicio_no_disponible";
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
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ec="${SRI_NS}">
  <soapenv:Header/>
  <soapenv:Body>
    <ec:consultarEstadoAutorizacionComprobante>
      <ec:claveAcceso>${claveAcceso}</ec:claveAcceso>
    </ec:consultarEstadoAutorizacionComprobante>
  </soapenv:Body>
</soapenv:Envelope>`;
}

function parseXmlResponse(xmlText: string): SRIResultado {
  const parser = new DOMParser();
  const doc = parser.parseFromString(xmlText, "text/xml");

  const faultEl =
    doc.querySelector("Body > Fault") ||
    doc.querySelector("Body > *|Fault");
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

  const estadoConsulta = getTextContent(doc, "estadoConsulta");
  const estadoAutorizacion = getTextContent(doc, "estadoAutorizacion");
  const rucEmisor = getTextContent(doc, "rucEmisor");
  const fechaAutorizacion = getTextContent(doc, "fechaAutorizacion");
  const mensajes = doc.querySelectorAll("mensaje");
  let primerMensaje: string | null = null;
  if (mensajes.length > 0) {
    const msgEl = mensajes[0].querySelector("mensaje");
    if (msgEl) {
      primerMensaje = msgEl.textContent;
    }
  }

  if (!estadoConsulta && !estadoAutorizacion) {
    return {
      estado: "servicio_no_disponible",
      ruc_emisor: null,
      fecha_autorizacion: null,
      monto: null,
      nombre_comprador: null,
      mensaje_sri: "Respuesta del SRI sin campos reconocidos",
    };
  }

  let estado: SRIResultado["estado"];
  if (
    estadoAutorizacion?.toUpperCase() === "AUTORIZADO" ||
    estadoConsulta?.toUpperCase() === "AUTORIZADO"
  ) {
    estado = "autorizado";
  } else if (
    estadoAutorizacion?.toUpperCase().includes("NO AUTORIZADO") ||
    estadoConsulta?.toUpperCase().includes("NO AUTORIZADO")
  ) {
    estado = "no_autorizado";
  } else if (
    estadoAutorizacion?.toUpperCase().includes("RECHAZADO") ||
    estadoConsulta?.toUpperCase().includes("RECHAZADO") ||
    estadoConsulta?.toUpperCase() === "CLAVE DE ACCESO REGISTRADA"
  ) {
    estado = "rechazada";
  } else {
    estado = "no_autorizado";
  }

  return {
    estado,
    ruc_emisor: rucEmisor || null,
    fecha_autorizacion: fechaAutorizacion || null,
    monto: null,
    nombre_comprador: null,
    mensaje_sri: primerMensaje,
  };
}

function getTextContent(doc: Document, tagName: string): string | null {
  const el = doc.getElementsByTagName(tagName)[0];
  return el?.textContent?.trim() || null;
}

export async function consultarSRI(clave: string): Promise<SRIResultado> {
  const envelope = buildSoapEnvelope(clave);

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), SRI_TIMEOUT_MS);

  try {
    const response = await fetch(SRI_WSDL_URL, {
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
    return parseXmlResponse(xmlText);
  } catch (err) {
    clearTimeout(timeoutId);
    const msg =
      err instanceof Error && err.name === "AbortError"
        ? "Timeout del SRI (>10s)"
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
