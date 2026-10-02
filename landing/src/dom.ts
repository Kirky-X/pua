// Tiny DOM builder so the landing pages stay framework-free: App.tsx and the
// page modules describe elements declaratively and el() materializes them.

export interface ElementSpec {
  tag: string;
  className?: string;
  text?: string;
  attrs?: Readonly<Record<string, string>>;
  children?: ReadonlyArray<Node | string | null | undefined>;
}

export function el(spec: ElementSpec): HTMLElement {
  const node = document.createElement(spec.tag);
  if (spec.className) node.className = spec.className;
  if (spec.text !== undefined) node.textContent = spec.text;
  if (spec.attrs) {
    for (const [name, value] of Object.entries(spec.attrs)) {
      node.setAttribute(name, value);
    }
  }
  if (spec.children) {
    for (const child of spec.children) {
      if (child === null || child === undefined) continue;
      node.append(typeof child === "string" ? document.createTextNode(child) : child);
    }
  }
  return node;
}
