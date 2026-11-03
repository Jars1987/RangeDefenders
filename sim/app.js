/* The human badge runs the unmodified main.lua. Bots use real demo rules. */
(async () => {
  const $ = (s) => document.querySelector(s),
    screen = $("#badge"),
    arena = $("#arena");
  let session = crypto.randomUUID().replaceAll("-", "").slice(0, 8),
    id = `s${session}_0`,
    players = [],
    nearby = [],
    positions = null,
    network = true,
    clock = 0,
    vm,
    closed = false,
    seq = 0;
  const widgets = new Map(),
    messages = [],
    replies = [],
    outbound = [],
    localStore = new Map();
  let lastRoom = 0,
    lastBot = 0,
    drag = null,
    requesting = false;
  const toast = (text) => {
    $("#toast").textContent = text;
    $("#toast").classList.add("visible");
    setTimeout(() => $("#toast").classList.remove("visible"), 2600);
  };
  function updatePlayers() {
    for (const p of players) {
      let el = $(`[data-id="${p.id}"]`);
      if (!el) {
        el = document.createElement("button");
        el.type = "button";
        el.className = "dot";
        el.dataset.id = p.id;
        el.innerHTML = "<i></i><span></span>";
        el.setAttribute("aria-label", "Move " + p.n);
        el.addEventListener("pointerdown", (event) => {
          drag = p.id;
          el.setPointerCapture(event.pointerId);
        });
        el.addEventListener("pointermove", (event) => {
          if (drag !== p.id) return;
          const r = arena.getBoundingClientRect();
          p.x = Math.max(
            6,
            Math.min(94, ((event.clientX - r.left) / r.width) * 100),
          );
          p.y = Math.max(
            10,
            Math.min(90, ((event.clientY - r.top) / r.height) * 100),
          );
          positions = players.map((p) => ({ x: p.x, y: p.y }));
          el.style.left = p.x + "%";
          el.style.top = p.y + "%";
        });
        el.addEventListener("pointerup", () => {
          drag = null;
        });
        arena.append(el);
      }
      el.className = "dot " + (p.status === "you" ? "you" : p.status);
      el.style.left = p.x + "%";
      el.style.top = p.y + "%";
      el.querySelector("span").textContent = p.n;
    }
    $("#players").replaceChildren(
      ...players.map((p) => {
        const el = document.createElement("div");
        el.className = "player";
        const a = document.createElement("span"),
          b = document.createElement("span");
        a.textContent = p.n;
        b.textContent = p.status === "you" ? "You" : p.status;
        el.append(a, b);
        return el;
      }),
    );
  }
  async function syncRoom() {
    if (requesting || !network) return;
    requesting = true;
    try {
      const res = await fetch("/demo/session", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ session, positions }),
      });
      const b = await res.json();
      if (!b.ok) throw Error(b.error);
      players = b.players;
      nearby = b.nearby;
      updatePlayers();
    } catch (e) {
      toast("Server unavailable");
    } finally {
      requesting = false;
    }
  }
  await syncRoom();
  const factory = new wasmoon.LuaFactory(location.origin + "/sim/glue.wasm");
  vm = await factory.createEngine();
  const set = (name, fn) => vm.global.set(name, fn);
  set("host_create", (kind, x, y, w, h, text, options) => {
    const id = ++seq,
      el = document.createElement("div"),
      o = JSON.parse(options);
    el.className = "widget " + kind;
    el.style.cssText = `left:${x}px;top:${y}px;width:${w}px;min-height:${h}px;font-size:${o.size || 14}px;color:${o.color === "green" ? "#a5f7c6" : "#ecf4ec"};text-align:${o.align || "left"}`;
    if (kind === "qr") {
      if (text.startsWith("https://example.trycloudflare.com")) {
        const link = new URL(text);
        text = location.origin + link.pathname + link.search;
      }
      const image = document.createElement("img");
      image.src = "/sim/qr?text=" + encodeURIComponent(text);
      image.alt = "Install / result QR";
      const a = document.createElement("a");
      a.setAttribute("aria-label", "Open page");
      a.href = text;
      a.target = "_blank";
      a.rel = "noopener";
      a.append(image);
      el.append(a);
    } else el.textContent = text;
    widgets.set(id, el);
    screen.append(el);
    return id;
  });
  set("host_change", (id, k, v) => {
    const el = widgets.get(id);
    if (!el) return;
    if (k === "text") el.textContent = v;
    else if (k === "show") el.hidden = v !== "1";
    else if (k === "remove") {
      el.remove();
      widgets.delete(id);
    } else if (k === "color") el.style.color = v;
    else if (k === "x") el.style.left = v + "px";
    else if (k === "y") el.style.top = v + "px";
  });
  set("host_hint", (s) => ($("#hint").textContent = s));
  set("host_toast", toast);
  set("host_led", (r, g, b) => {
    for (const el of $("#leds").children) {
      el.style.backgroundColor = `rgb(${r},${g},${b})`;
      el.style.boxShadow =
        r + g + b ? `0 0 10px rgb(${r},${g},${b},.45)` : "none";
    }
  });
  set("host_millis", () => clock);
  set("host_id", () => id);
  set("host_exit", () => {
    closed = true;
    toast("App closed. Start a new room.");
  });
  set("host_nearby", () => JSON.stringify(nearby));
  set("host_mesh", (s) => messages.push(s));
  set("host_storage", (action, k, v) => {
    if (action === "get") return localStore.get(k);
    if (action === "set") localStore.set(k, v);
    else localStore.delete(k);
  });
  set("host_call", (rid, kind, json) =>
    outbound.push({ rid, kind, data: JSON.parse(json) }),
  );
  const [codec, shim, main] = await Promise.all(
    ["/sim/json.lua", "/sim/shim.lua", "/sim/main.lua"].map((p) =>
      fetch(p).then((r) => r.text()),
    ),
  );
  await vm.doString(
    "json=(function()\n" + codec + "\nend)()\n" + shim + "\n" + main,
  );
  $("#connection").textContent = "Connecting";
  const key = (k) => {
    if (!closed) vm.global.get("on_key")(k, false);
  };
  document
    .querySelectorAll("[data-key]")
    .forEach((button) =>
      button.addEventListener("click", () => key(button.dataset.key)),
    );
  document.addEventListener("keydown", (event) => {
    const k = {
      ArrowUp: "up",
      ArrowDown: "down",
      ArrowLeft: "left",
      ArrowRight: "right",
      Enter: "select",
      Escape: "back",
    }[event.key];
    if (
      k &&
      !["INPUT", "SUMMARY", "BUTTON", "A"].includes(
        document.activeElement.tagName,
      )
    ) {
      event.preventDefault();
      key(k);
    }
  });
  $("#network").addEventListener("change", (event) => {
    network = !event.target.checked;
    $("#connection").textContent = network ? "Connected" : "Offline";
  });
  $("#reset").addEventListener("click", () => location.reload());
  $("#gather").addEventListener("click", () => {
    positions = players.map((p, j) => ({
      x: 42 + (j % 3) * 8,
      y: 43 + Math.floor(j / 3) * 14,
    }));
    syncRoom();
  });
  $("#separate").addEventListener("click", () => {
    positions = players.map((p, j) => ({
      x: 8 + (j % 3) * 42,
      y: 12 + Math.floor(j / 3) * 76,
    }));
    syncRoom();
  });
  async function dispatch(job) {
    const { rid, kind, data } = job;
    if (kind === "profile") {
      replies.push([rid, true, JSON.stringify({ name: "@you", x: null })]);
      return;
    }
    if (kind === "award") {
      replies.push([rid, true, JSON.stringify({ awarded: 0 })]);
      return;
    }
    if (kind === "confirm") {
      replies.push([rid, true, JSON.stringify(window.confirm(data.text))]);
      return;
    }
    if (kind === "http") {
      if (!network) {
        replies.push([rid, false, JSON.stringify("offline")]);
        return;
      }
      try {
        const target = new URL(data.url),
          res = await fetch(target.pathname + target.search, {
            method: "POST",
            headers: {
              "content-type": "application/json",
              "X-Demo-Badge": id,
              "X-Demo-User": `s${session}_u0`,
            },
            body: JSON.stringify(data.body),
          });
        const text = await res.text();
        if (data.url.endsWith("/v1/hello"))
          $("#connection").textContent = res.ok ? "Connected" : "Offline";
        replies.push([rid, true, text, res.status]);
      } catch {
        replies.push([rid, false, JSON.stringify("offline")]);
      }
    }
  }
  setInterval(() => {
    if (closed) return;
    clock += 50;
    while (replies.length) vm.global.get("sim_reply")(...replies.shift());
    vm.global.get("on_tick")(50);
    while (outbound.length) dispatch(outbound.shift());
    if (messages.length > 8) messages.splice(0, messages.length - 8);
    if (clock - lastRoom >= 2000) {
      lastRoom = clock;
      if (players.length && !drag) {
        positions = players.map((p, j) => ({
          x:
            j === 0
              ? p.x
              : Math.max(
                  8,
                  Math.min(92, p.x + Math.sin(clock / 4000 + j) * 0.35),
                ),
          y:
            j === 0
              ? p.y
              : Math.max(
                  10,
                  Math.min(90, p.y + Math.cos(clock / 4000 + j) * 0.35),
                ),
        }));
      }
      syncRoom();
    }
  }, 50);
  // Read-only diagnostics for the browser smoke runner.
  window.bp26 = {
    key,
    get id() {
      return id;
    },
    get widgets() {
      return widgets.size;
    },
    get players() {
      return players;
    },
    get clock() {
      return clock;
    },
  };
})().catch((error) => {
  document.querySelector("#connection").textContent = "Could not start";
  document.querySelector("#runtime").textContent = error.message;
  console.error(error);
});
