import { readFileSync, writeFileSync } from "node:fs";

const [input, output, title] = process.argv.slice(2);
const text = readFileSync(input, "utf8");
const base16 = ["#1e1e1e", "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd", "#56b6c2", "#dcdfe4",
  "#5c6370", "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd", "#56b6c2", "#ffffff"];
function color256(n) {
  if (n < 16) return base16[n];
  if (n < 232) {
    const v = n - 16;
    const c = [Math.floor(v / 36), Math.floor(v / 6) % 6, v % 6].map((x) => (x === 0 ? 0 : 55 + x * 40));
    return `rgb(${c.join(",")})`;
  }
  const g = 8 + (n - 232) * 10;
  return `rgb(${g},${g},${g})`;
}
const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
let state = { fg: null, bg: null, bold: false, dim: false, italic: false, underline: false };
let html = "";
let open = false;
function style() {
  const parts = [];
  if (state.fg) parts.push(`color:${state.fg}`);
  if (state.bg) parts.push(`background:${state.bg}`);
  if (state.bold) parts.push("font-weight:bold");
  if (state.dim) parts.push("opacity:0.6");
  if (state.italic) parts.push("font-style:italic");
  if (state.underline) parts.push("text-decoration:underline");
  return parts.join(";");
}
function apply(params) {
  const p = params.length ? params : [0];
  for (let i = 0; i < p.length; i++) {
    const n = p[i];
    if (n === 0) state = { fg: null, bg: null, bold: false, dim: false, italic: false, underline: false };
    else if (n === 1) state.bold = true;
    else if (n === 2) state.dim = true;
    else if (n === 3) state.italic = true;
    else if (n === 4) state.underline = true;
    else if (n === 22) { state.bold = false; state.dim = false; }
    else if (n === 23) state.italic = false;
    else if (n === 24) state.underline = false;
    else if (n >= 30 && n <= 37) state.fg = base16[n - 30];
    else if (n >= 90 && n <= 97) state.fg = base16[n - 82];
    else if (n === 39) state.fg = null;
    else if (n >= 40 && n <= 47) state.bg = base16[n - 40];
    else if (n >= 100 && n <= 107) state.bg = base16[n - 92];
    else if (n === 49) state.bg = null;
    else if (n === 38 || n === 48) {
      const key = n === 38 ? "fg" : "bg";
      if (p[i + 1] === 5) { state[key] = color256(p[i + 2]); i += 2; }
      else if (p[i + 1] === 2) { state[key] = `rgb(${p[i + 2]},${p[i + 3]},${p[i + 4]})`; i += 4; }
    }
  }
}
const re = /\x1b\[([0-9;:]*)m|\x1b\[[0-9;?]*[A-Za-z]|\x1b\][^\x07]*\x07/g;
let last = 0;
let m;
const flush = (s) => {
  if (!s) return;
  html += `<span style="${style()}">${esc(s)}</span>`;
};
while ((m = re.exec(text))) {
  flush(text.slice(last, m.index));
  if (m[1] !== undefined && m[0].endsWith("m")) apply(m[1].split(/[;:]/).filter((x) => x !== "").map(Number));
  last = re.lastIndex;
}
flush(text.slice(last));
writeFileSync(output, `<!doctype html><html><head><meta charset="utf-8"><title>${esc(title ?? "")}</title>
<style>body{margin:0;background:#1e1e1e;color:#dcdfe4;font-family:"DejaVu Sans Mono",monospace}
h1{font:600 14px sans-serif;color:#e5c07b;background:#111;margin:0;padding:8px 12px}
pre{margin:0;padding:8px 12px;font-size:13px;line-height:1.25;white-space:pre}</style></head>
<body><h1>${esc(title ?? "")}</h1><pre>${html}</pre></body></html>`);
