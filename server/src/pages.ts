import type { Engine } from "./engine";
export const escape = (s: unknown) =>
  String(s ?? "").replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ]!,
  );
const style = `body{margin:0;background:#0b1318;color:#f3f4ec;font:16px -apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif}main{max-width:1000px;margin:7vh auto;padding:32px}h1{font-size:clamp(40px,7vw,82px);letter-spacing:-.06em;margin:0 0 32px}h2{font-size:24px}a{color:#90f8bf}section{padding:24px 0;border-top:1px solid #354149}li{padding:12px}small{color:#aebbb8}button,.button{display:inline-block;background:#a7f8cb;color:#102820;border:0;border-radius:30px;padding:14px 24px;text-decoration:none;margin:8px 10px 8px 0}strong{font-variant-numeric:tabular-nums}`;
export function page(title: string, body: string, refresh = false) {
  return `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">${refresh ? '<meta http-equiv="refresh" content="5">' : ""}<title>${escape(title)}</title><style>${style}</style><main>${body}</main></html>`;
}
export function live(e: Engine, ns: string) {
  const rooms = Object.values(e.state.rooms)
    .filter((r) => r.ns === ns)
    .slice(-8)
    .reverse();
  return page(
    "Range live",
    `<h1>Lazarus is in the room.</h1><p>Big Drop in <strong>${e.bigIn()}s</strong>${ns === "demo" ? " / Demo - no rewards" : ""}</p><section><h2>Rounds</h2>${rooms.map((r) => `<p><strong>${escape(r.result ?? r.phase.toUpperCase())}</strong> / ${r.members.length} players / ${r.big ? "Big Drop" : r.ranked ? "Prize round" : "Unranked"}${r.winner ? " / " + escape(e.peer(r.ns, r.winner)?.name) : ""}</p>`).join("") || "<p>No rounds yet</p>"}</section><section><h2>Solana Defenders</h2><ol>${e
      .top(ns, 10)
      .map((s) => `<li>${escape(s.n)} <strong>${s.s}</strong></li>`)
      .join(
        "",
      )}</ol><small>Informal scores. Finals at the Range booth.</small></section>`,
    true,
  );
}
export function resultPage(share: { app: string; text: string }) {
  const install = `/go/install?a=${share.app}`,
    intent =
      "https://twitter.com/intent/tweet?text=" +
      encodeURIComponent(share.text + " @range_org");
  return page(
    "Range result",
    `<h1>${escape(share.text)}</h1><a class="button" href="${install}">Install ${share.app === "lazarus" ? "Lazarus" : "Defenders"}</a><a class="button" href="${escape(intent)}" rel="noopener noreferrer" target="_blank">Post on X</a><p><a href="/go/screening?a=${share.app}">Range transaction screening</a></p>`,
  );
}
