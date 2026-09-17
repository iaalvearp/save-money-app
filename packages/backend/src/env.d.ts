declare module "hono/types" {
  interface ContextVariableMap {
    user: { sub: number; rol: string };
  }
}

declare class DOMParser {
  parseFromString(html: string, type: "text/html"): Document;
  parseFromString(xml: string, type: "text/xml"): Document;
}

interface Element {
  tagName: string;
  textContent: string | null;
  getElementsByTagName(name: string): HTMLCollectionOf<Element>;
  querySelector(selectors: string): Element | null;
}

interface HTMLCollectionOf<T> {
  length: number;
  [index: number]: T;
}

interface Document {
  getElementsByTagName(name: string): HTMLCollectionOf<Element>;
  querySelector(selectors: string): Element | null;
  querySelectorAll(selectors: string): NodeListOf<Element>;
}

interface NodeListOf<T> {
  length: number;
  [index: number]: T;
  forEach(callbackfn: (value: T, key: number) => void): void;
}
