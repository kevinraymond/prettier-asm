// The doc text form shared with src/debugdoc.s.
//
// docToText(doc, { exact }) writes a Prettier doc. Normalized (the default)
// flattens arrays, drops "" and merges adjacent strings; exact keeps arrays
// and strings as they are and labels shared arrays too. textToDoc reads
// either form back into Prettier doc objects (shared `$N` become one object,
// `#N` become symbols).

const CONTAINERS = new Set([
  "indent", "align", "group", "fill", "if-break", "indent-if-break",
  "line-suffix", "label", "__tostr",
]);
const LABEL_KEYS = ["embed", "hug", "memberChain", "tagged"];

function isEmpty(doc) {
  return doc === "" || doc === undefined || doc === null;
}

function labelText(label) {
  if (typeof label !== "object" || label === null) {
    throw new Error("label is not an object: " + JSON.stringify(label));
  }
  const keys = Object.keys(label).filter((k) => label[k] !== undefined).sort();
  for (const k of keys) {
    if (!LABEL_KEYS.includes(k) || typeof label[k] !== "boolean") {
      throw new Error("label key not ported: " + k);
    }
    if (k !== "hug" && label[k] !== true) {
      throw new Error("label value not ported: " + k + "=" + label[k]);
    }
  }
  return keys.map((k) => `${k}=${label[k]}`).join(",");
}

export function docToText(doc, { exact = false } = {}) {
  const refs = new Map();
  const labels = new Map();
  const ids = new Map();
  let nextLabel = 0;
  const out = [];

  const isShareable = (d) =>
    d !== null && typeof d === "object" &&
    (Array.isArray(d) ? exact : CONTAINERS.has(d.type));

  // count references in the traversal the writer makes
  const count = (d) => {
    if (isEmpty(d) || typeof d === "string") return;
    if (Array.isArray(d) && !exact) {
      for (const p of d) count(p);
      return;
    }
    if (!isShareable(d)) return;
    const n = (refs.get(d) ?? 0) + 1;
    refs.set(d, n);
    if (n > 1) return;
    if (Array.isArray(d)) for (const p of d) count(p);
    else children(d).forEach(count);
  };

  const children = (d) => {
    switch (d.type) {
      case "group":
        if (!d.expandedStates) return [d.contents];
        return d.contents === d.expandedStates[0] ? d.expandedStates : [d.contents, ...d.expandedStates];
      case "fill":
        return d.parts;
      case "if-break":
        return [d.breakContents, d.flatContents];
      default:
        return [d.contents];
    }
  };

  const id = (sym) => {
    if (!ids.has(sym)) ids.set(sym, ids.size + 1);
    return "#" + ids.get(sym);
  };

  const flatten = (d, items) => {
    if (isEmpty(d)) return;
    if (Array.isArray(d)) {
      for (const p of d) flatten(p, items);
      return;
    }
    if (typeof d === "string" && typeof items.at(-1) === "string") {
      items[items.length - 1] += d;
    } else {
      items.push(d);
    }
  };

  const emit = (d) => {
    if (exact) {
      if (isEmpty(d)) return out.push('""');
      if (typeof d === "string") return out.push(JSON.stringify(d));
      return emitOne(d);
    }
    const items = [];
    flatten(d, items);
    if (items.length === 0) return out.push('""');
    if (items.length > 1) out.push("[");
    items.forEach((item, i) => {
      if (i > 0) out.push(" ");
      if (typeof item === "string") out.push(JSON.stringify(item));
      else emitOne(item);
    });
    if (items.length > 1) out.push("]");
  };

  const emitOne = (d) => {
    if (isShareable(d) && refs.get(d) > 1) {
      if (labels.has(d)) return out.push("$" + labels.get(d));
      labels.set(d, ++nextLabel);
      out.push("$" + nextLabel + "=");
    }
    if (Array.isArray(d)) {
      out.push("[");
      d.forEach((p, i) => {
        if (i > 0) out.push(" ");
        emit(p);
      });
      return out.push("]");
    }
    switch (d.type) {
      case "line":
        return out.push(d.literal ? "lit" : d.hard ? "hard" : d.soft ? "soft" : "line");
      case "break-parent":
        return out.push("bp");
      case "line-suffix-boundary":
        return out.push("lsb");
      case "trim":
        return out.push("trim");
      case "cursor":
        return out.push("cursor");
      case "indent":
        out.push("(indent ");
        emit(d.contents);
        return out.push(")");
      case "__tostr":
        out.push("(tostr " + optionsText(d.options) + " ");
        emit(d.contents);
        return out.push(")");
      case "line-suffix":
        out.push("(lsuffix ");
        emit(d.contents);
        return out.push(")");
      case "label":
        out.push("(label " + JSON.stringify(labelText(d.label)) + " ");
        emit(d.contents);
        return out.push(")");
      case "align": {
        const n = d.n;
        let text;
        if (n === Number.NEGATIVE_INFINITY) text = "-inf";
        else if (typeof n === "number") {
          if (!Number.isInteger(n)) throw new Error("align with " + n);
          text = String(n);
        } else if (typeof n === "string") text = JSON.stringify(n);
        else if (n && n.type === "root") text = "root";
        else throw new Error("align with " + JSON.stringify(n));
        out.push("(align " + text + " ");
        emit(d.contents);
        return out.push(")");
      }
      case "group": {
        const own = d.expandedStates && d.contents !== d.expandedStates[0];
        out.push(d.expandedStates ? (own ? "(cgroup*" : "(cgroup") : "(group");
        if (d.break) out.push(d.break === "propagated" ? " pbreak" : " break");
        if (d.id) out.push(" " + id(d.id));
        if (d.expandedStates) {
          if (own) {
            out.push(" ");
            emit(d.contents);
          }
          for (const s of d.expandedStates) {
            out.push(" ");
            emit(s);
          }
        } else {
          out.push(" ");
          emit(d.contents);
        }
        return out.push(")");
      }
      case "fill":
        out.push("(fill");
        for (const p of d.parts) {
          out.push(" ");
          emit(p);
        }
        return out.push(")");
      case "if-break":
        out.push("(ifbreak ");
        emit(d.breakContents);
        out.push(" ");
        emit(d.flatContents);
        if (d.groupId) out.push(" " + id(d.groupId));
        return out.push(")");
      case "indent-if-break":
        out.push("(iib ");
        if (d.negate) out.push("negate ");
        if (d.groupId) out.push(id(d.groupId) + " ");
        emit(d.contents);
        return out.push(")");
      default:
        throw new Error("unknown doc " + JSON.stringify(d).slice(0, 80));
    }
  };

  count(doc);
  emit(doc);
  return out.join("");
}

const LEAVES = {
  line: { type: "line" },
  soft: { type: "line", soft: true },
  hard: { type: "line", hard: true },
  lit: { type: "line", hard: true, literal: true },
  bp: { type: "break-parent" },
  lsb: { type: "line-suffix-boundary" },
  trim: { type: "trim" },
  cursor: { type: "cursor" },
};

// textToDoc(text) -> doc. Leaves are fresh objects; hardline parts are not
// Prettier's own constants, which only matters for identity.
export function textToDoc(text) {
  let i = 0;
  const labels = new Map();
  const ids = new Map();
  const ws = () => {
    while (i < text.length && " \n\t\r".includes(text[i])) i++;
  };
  const peek = () => (ws(), text[i]);
  const expect = (c) => {
    if (peek() !== c) throw new Error(`expected ${c} at ${i}: ${text.slice(i, i + 40)}`);
    i++;
  };
  const word = () => {
    ws();
    const m = /^[-_.0-9A-Za-z]+\*?/.exec(text.slice(i, i + 64));
    if (!m) throw new Error("expected a word at " + i);
    i += m[0].length;
    return m[0];
  };
  const str = () => {
    ws();
    const m = /^"(?:[^"\\]|\\.)*"/su.exec(text.slice(i));
    if (!m) throw new Error("expected a string at " + i);
    i += m[0].length;
    return JSON.parse(m[0]);
  };
  const id = () => {
    expect("#");
    const n = word();
    if (!ids.has(n)) ids.set(n, Symbol("g" + n));
    return ids.get(n);
  };
  const doc = () => {
    const c = peek();
    if (c === '"') return str();
    if (c === "[") {
      i++;
      const parts = [];
      while (peek() !== "]") parts.push(doc());
      i++;
      return parts;
    }
    if (c === "$") {
      i++;
      const n = word();
      if (text[i] === "=") {
        i++;
        const d = doc();
        labels.set(n, d);
        return d;
      }
      if (!labels.has(n)) throw new Error("unknown label $" + n);
      return labels.get(n);
    }
    if (c === "(") {
      i++;
      const head = word();
      const d = container(head);
      expect(")");
      return d;
    }
    const w = word();
    if (!(w in LEAVES)) throw new Error("unknown word " + w);
    return { ...LEAVES[w] };
  };
  const groupFlags = () => {
    const g = { break: false };
    for (;;) {
      const c = peek();
      if (c === "#") g.id = id();
      else if (text.startsWith("break", i) && !/[a-z]/.test(text[i + 5])) {
        i += 5;
        g.break = true;
      } else if (text.startsWith("pbreak", i)) {
        i += 6;
        g.break = "propagated";
      } else return g;
    }
  };
  const container = (head) => {
    switch (head) {
      case "indent":
        return { type: "indent", contents: doc() };
      case "lsuffix":
        return { type: "line-suffix", contents: doc() };
      case "label": {
        const t = str();
        const label = {};
        for (const kv of t ? t.split(",") : []) {
          const [k, v] = kv.split("=");
          label[k] = v === "true";
        }
        return { type: "label", label, contents: doc() };
      }
      case "align": {
        let n;
        if (peek() === '"') n = str();
        else {
          const w = word();
          n = w === "-inf" ? Number.NEGATIVE_INFINITY : w === "root" ? { type: "root" } : Number(w);
        }
        return { type: "align", contents: doc(), n };
      }
      case "group": {
        const g = groupFlags();
        return { type: "group", id: g.id, contents: doc(), break: g.break, expandedStates: undefined };
      }
      case "cgroup":
      case "cgroup*": {
        const g = groupFlags();
        const contents = head === "cgroup*" ? doc() : undefined;
        const states = [];
        while (peek() !== ")") states.push(doc());
        return { type: "group", id: g.id, contents: contents ?? states[0], break: g.break, expandedStates: states };
      }
      case "fill": {
        const parts = [];
        while (peek() !== ")") parts.push(doc());
        return { type: "fill", parts };
      }
      case "ifbreak": {
        const breakContents = doc();
        const flatContents = doc();
        const groupId = peek() === "#" ? id() : undefined;
        return { type: "if-break", breakContents, flatContents, groupId };
      }
      case "iib": {
        let negate = false;
        ws();
        if (text.startsWith("negate", i)) {
          i += 6;
          negate = true;
        }
        const groupId = peek() === "#" ? id() : undefined;
        return { type: "indent-if-break", contents: doc(), groupId, negate };
      }
      default:
        throw new Error("unknown head " + head);
    }
  };
  const d = doc();
  if (peek() !== undefined) throw new Error("trailing text at " + i);
  return d;
}

// optionsText({printWidth, tabWidth, useTabs, endOfLine}) -> "W TW TABS EOL"
export function optionsText(o) {
  const w = o.printWidth === Number.POSITIVE_INFINITY ? "inf" : String(o.printWidth);
  return `${w} ${o.tabWidth} ${o.useTabs ? 1 : 0} ${o.endOfLine}`;
}

// parseBlocks(buffer) -> array of strings from "<len>\n<bytes>\n" blocks
export function parseBlocks(buf) {
  const blocks = [];
  let i = 0;
  while (i < buf.length) {
    const nl = buf.indexOf(10, i);
    if (nl < 0) throw new Error("truncated block header");
    const len = Number(buf.subarray(i, nl).toString("latin1"));
    const start = nl + 1;
    blocks.push(buf.subarray(start, start + len).toString("utf8"));
    i = start + len + 1;
  }
  return blocks;
}
