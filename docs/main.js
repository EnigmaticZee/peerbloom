// Peerbloom website: motion and the live demos. No libraries, no tracking.
(() => {
  const params = new URLSearchParams(location.search);
  const shot = params.get("shot");                 // README screenshots: ?shot=window&theme=ocean
  const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches || !!shot;
  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => [...el.querySelectorAll(s)];

  if (shot) document.body.classList.add("shot");

  // Nav background once the page scrolls.
  const nav = $("#nav");
  const onScroll = () => nav.classList.toggle("scrolled", scrollY > 20);
  addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  // Scroll reveal, staggered within each group.
  const groups = new Map();
  $$(".reveal").forEach((el) => {
    const key = el.parentElement;
    const i = groups.get(key) ?? 0;
    groups.set(key, i + 1);
    el.style.setProperty("--d", `${Math.min(i, 6) * 0.08}s`);
  });
  if (reduced) {
    $$(".reveal").forEach((el) => el.classList.add("in"));
  } else {
    const io = new IntersectionObserver((entries) => {
      entries.forEach((e) => { if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); } });
    }, { threshold: 0.12, rootMargin: "0px 0px -40px 0px" });
    $$(".reveal").forEach((el) => io.observe(el));
  }

  // Cards: a soft light follows the pointer.
  $$(".card").forEach((card) => {
    card.addEventListener("pointermove", (e) => {
      const r = card.getBoundingClientRect();
      card.style.setProperty("--mx", `${e.clientX - r.left}px`);
      card.style.setProperty("--my", `${e.clientY - r.top}px`);
    });
  });

  // MARK: Hero swarm: pieces from peers fly into the icon; a few amber ones fly out (seeding).
  const canvas = $("#swarm");
  if (canvas && !reduced) {
    const ctx = canvas.getContext("2d");
    const icon = $(".hero-icon");
    const colors = ["#3c6bff", "#2f8cf0", "#26b8f0", "#2de1c2"];
    let w = 0, h = 0, dpr = 1, cx = 0, cy = 0, running = true, particles = [];

    const resize = () => {
      dpr = Math.min(devicePixelRatio || 1, 2);
      w = canvas.clientWidth; h = canvas.clientHeight;
      canvas.width = w * dpr; canvas.height = h * dpr;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      const c = canvas.getBoundingClientRect(), i = icon.getBoundingClientRect();
      cx = i.left - c.left + i.width / 2; cy = i.top - c.top + i.height / 2;
    };
    const spawn = (p = {}) => {
      const out = Math.random() < 0.15;
      const a = Math.random() * Math.PI * 2;
      const far = Math.hypot(w, h) * (0.45 + Math.random() * 0.25);
      return Object.assign(p, {
        out, t: 0, speed: 0.0025 + Math.random() * 0.004,
        x0: cx + Math.cos(a) * (out ? 60 : far), y0: cy + Math.sin(a) * (out ? 60 : far),
        x1: cx + Math.cos(a) * (out ? far : 70), y1: cy + Math.sin(a) * (out ? far : 70),
        size: 4 + Math.random() * 6, rot: Math.random() * Math.PI, spin: (Math.random() - 0.5) * 0.04,
        color: out ? "#f5a04a" : colors[(Math.random() * colors.length) | 0],
      });
    };
    const count = () => (w < 700 ? 28 : 70);
    const ease = (t) => 1 - Math.pow(1 - t, 3);

    const frame = () => {
      if (!running) return;
      ctx.clearRect(0, 0, w, h);
      for (const p of particles) {
        p.t += p.speed; p.rot += p.spin;
        if (p.t >= 1) { spawn(p); continue; }
        const e = ease(p.t);
        const x = p.x0 + (p.x1 - p.x0) * e, y = p.y0 + (p.y1 - p.y0) * e;
        const alpha = p.out ? 1 - p.t : Math.min(1, p.t * 3) * (1 - Math.pow(p.t, 6));
        // Motion trail.
        const back = Math.max(0, e - 0.06);
        ctx.strokeStyle = p.color; ctx.globalAlpha = alpha * 0.25; ctx.lineWidth = p.size * 0.6; ctx.lineCap = "round";
        ctx.beginPath(); ctx.moveTo(p.x0 + (p.x1 - p.x0) * back, p.y0 + (p.y1 - p.y0) * back); ctx.lineTo(x, y); ctx.stroke();
        // The piece: a small rounded tile.
        ctx.globalAlpha = alpha * 0.9; ctx.fillStyle = p.color;
        ctx.save(); ctx.translate(x, y); ctx.rotate(p.rot);
        const s = p.size, r = s * 0.28;
        ctx.beginPath(); ctx.roundRect(-s / 2, -s / 2, s, s, r); ctx.fill();
        ctx.restore();
      }
      ctx.globalAlpha = 1;
      requestAnimationFrame(frame);
    };

    resize();
    particles = Array.from({ length: count() }, () => { const p = spawn(); p.t = Math.random(); return p; });
    addEventListener("resize", () => { resize(); particles.length = 0; for (let i = 0; i < count(); i++) particles.push(spawn()); });
    new IntersectionObserver(([e]) => { const was = running; running = e.isIntersecting; if (running && !was) frame(); }).observe(canvas);
    frame();
  }

  // MARK: Live app demo
  const transfers = [
    { name: "ubuntu-26.04-desktop-amd64.iso", kind: "iso", size: 6.10, p: 0.62, dl: 18.4, ul: 1.2, peers: 142, state: "dl" },
    { name: "Fedora-Workstation-Live-44-x86_64.iso", kind: "iso", size: 2.30, p: 0.31, dl: 9.7, ul: 0.64, peers: 87, state: "dl" },
    { name: "Sintel (2010) 4K", kind: "mov", size: 4.2, p: 1, dl: 0, ul: 3.4, ratio: 2.41, state: "seed" },
    { name: "Big Buck Bunny 60fps 4K", kind: "mov", size: 1.4, p: 1, dl: 0, ul: 0.86, ratio: 5.12, state: "seed" },
    { name: "debian-13.2.0-amd64-netinst.iso", kind: "iso", size: 0.754, p: 0.84, dl: 4.1, ul: 0.3, peers: 54, state: "dl" },
    { name: "archlinux-2026.10.01-x86_64.iso", kind: "iso", size: 1.3, p: 0.08, dl: 0, ul: 0, state: "paused" },
  ];
  let vpnDown = false;
  const fmtRate = (mb) => (mb <= 0 ? "—" : mb >= 1 ? `${mb.toFixed(1)} MB/s` : `${Math.round(mb * 1024)} KB/s`);
  const fmtEta = (s) => (!isFinite(s) ? "—" : s >= 3600 ? `${Math.floor(s / 3600)}h ${Math.floor((s % 3600) / 60)}m` : s >= 60 ? `${Math.floor(s / 60)}m ${Math.floor(s % 60)}s` : `${Math.ceil(s)}s`);
  const live = (t) => !vpnDown && t.state !== "paused";
  const rateOf = (t, key) => (live(t) ? t[key] : 0);
  const eta = (t) => (t.size * (1 - t.p) * 1024) / rateOf(t, "dl");

  const status = (t) => {
    if (t.state === "paused") return "Paused";
    if (vpnDown) return "Waiting for VPN";
    if (t.state === "seed") return `Seeding · ratio ${t.ratio.toFixed(2)}`;
    return `Downloading · ${t.peers} peers · ${fmtEta(eta(t))}`;
  };
  const color = (t) => (t.state === "seed" ? "var(--ul)" : t.state === "paused" ? "var(--w-muted)" : "var(--dl)");

  const renderRows = (host, list, sel) => {
    if (!host) return;
    host.innerHTML = list.map((t, i) => `
      <div class="row${i === sel ? " sel" : ""}">
        <span class="name"><i class="badge ${t.kind}">${t.kind === "iso" ? "ISO" : "MOV"}</i>
          <span><b>${t.name}</b><small data-status="${i}">${status(t)}</small></span></span>
        <span class="bar"><i data-bar="${i}" style="--p:${(t.p * 100).toFixed(1)}%;--c:${color(t)}"></i><span data-pct="${i}">${Math.floor(t.p * 100)}%</span></span>
        <span class="num live-dl" data-dl="${i}">${fmtRate(rateOf(t, "dl"))}</span>
        <span class="num live-ul" data-ul="${i}">${fmtRate(rateOf(t, "ul"))}</span>
      </div>`).join("");
  };
  const mainRows = $("[data-rows]");
  const miniRows = $("[data-rows-mini]");
  renderRows(mainRows, transfers, 0);
  renderRows(miniRows, transfers.slice(0, 4), -1);

  // Piece map for the selected transfer: pieces arrive in a scattered order, like real swarms.
  const pieceHost = $("[data-pieces]");
  const PIECES = 200;
  const order = Array.from({ length: PIECES }, (_, i) => i);
  for (let i = PIECES - 1, s = 7; i > 0; i--) { s = (s * 9301 + 49297) % 233280; const j = Math.floor((s / 233280) * (i + 1)); [order[i], order[j]] = [order[j], order[i]]; }
  if (pieceHost) pieceHost.innerHTML = "<i></i>".repeat(PIECES);
  const cells = pieceHost ? [...pieceHost.children] : [];
  let shown = 0;
  const paintPieces = (p, animate) => {
    const want = Math.floor(p * PIECES);
    while (shown < want) {
      const c = cells[order[shown++]];
      if (!c) break;
      c.classList.add("have");
      if (animate) { c.classList.add("new"); setTimeout(() => c.classList.remove("new"), 700); }
    }
  };
  paintPieces(transfers[0].p, false);

  // Speed chart.
  const hist = { dl: [], ul: [] };
  for (let i = 0; i < 40; i++) { hist.dl.push(20 + Math.sin(i / 4) * 5 + i * 0.25); hist.ul.push(4 + Math.cos(i / 5)); }
  const path = (arr, max) => arr.map((v, i) => `${i ? "L" : "M"}${(i / (arr.length - 1)) * 240} ${70 - (v / max) * 62}`).join(" ");
  const drawChart = () => {
    const max = Math.max(36, ...hist.dl);
    $("[data-chart=dl]")?.setAttribute("d", path(hist.dl, max));
    $("[data-chart=ul]")?.setAttribute("d", path(hist.ul, max));
  };
  drawChart();

  const update = () => {
    let down = 0, up = 0;
    transfers.forEach((t, i) => {
      if (live(t)) {
        if (t.state === "dl") {
          t.dl = Math.max(0.5, t.dl * (0.9 + Math.random() * 0.2));
          t.p = Math.min(1, t.p + (t.dl * 0.8) / (t.size * 1024));
          if (t.p >= 1) { t.state = "seed"; t.ratio = 0.05; t.dl = 0; t.ul = 1.1; }
        } else if (t.state === "seed") {
          t.ul = Math.max(0.2, t.ul * (0.85 + Math.random() * 0.3));
          t.ratio += t.ul / (t.size * 1024);
        }
      }
      down += rateOf(t, "dl"); up += rateOf(t, "ul");
      $$(`[data-bar="${i}"]`).forEach((b) => { b.style.setProperty("--p", `${(t.p * 100).toFixed(1)}%`); b.style.setProperty("--c", color(t)); });
      $$(`[data-pct="${i}"]`).forEach((el) => (el.textContent = `${Math.floor(t.p * 100)}%`));
      $$(`[data-dl="${i}"]`).forEach((el) => (el.textContent = fmtRate(rateOf(t, "dl"))));
      $$(`[data-ul="${i}"]`).forEach((el) => (el.textContent = fmtRate(rateOf(t, "ul"))));
      $$(`[data-status="${i}"]`).forEach((el) => (el.textContent = status(t)));
    });
    $("[data-total=down]").textContent = fmtRate(down);
    $("[data-total=up]").textContent = fmtRate(up);
    const sel = transfers[0];
    paintPieces(sel.p, true);
    $("[data-insp-sub]").textContent = `${sel.state === "dl" ? `${sel.peers} peers · ` : ""}${(sel.size * sel.p).toFixed(2)} of ${sel.size.toFixed(2)} GB`;
    $("[data-eta]").textContent = sel.state === "dl" ? fmtEta(eta(sel)) : "Done";
    hist.dl.push(down); hist.dl.shift(); hist.ul.push(up); hist.ul.shift();
    drawChart();
    // Sidebar counts.
    const c = { dl: 0, seed: 0, paused: 0 };
    transfers.forEach((t) => c[t.state]++);
    const counts = $$(".side-i em");
    if (counts.length >= 4) { counts[1].textContent = c.dl; counts[2].textContent = c.seed; counts[3].textContent = c.paused; }
  };
  $("[data-eta]").textContent = fmtEta(eta(transfers[0]));
  if (!reduced) setInterval(update, 900);

  // MARK: VPN drop simulation (privacy section and the demo window).
  const toggle = $("#vpn-toggle");
  const tunnel = $("[data-tunnel]");
  const setVPN = (down) => {
    vpnDown = down;
    toggle.setAttribute("aria-pressed", String(down));
    toggle.textContent = down ? "Reconnect the VPN" : "Simulate a VPN drop";
    tunnel.classList.toggle("down", down);
    $("[data-pipe-label]").textContent = down ? "Tunnel down" : "VPN tunnel";
    $("[data-tunnel-status]").innerHTML = down
      ? '<span class="pill warn">Waiting for VPN</span> Nothing leaks. Transfers wait until your VPN is back.'
      : '<span class="pill ok">Protected</span> Traffic only goes through your VPN.';
    const card = $("[data-vpn]");
    card.classList.toggle("down", down);
    $("[data-vpn-title]").textContent = down ? "Waiting for VPN" : "Protected";
    $("[data-vpn-sub]").innerHTML = down ? "Transfers pause until a VPN connects. <b>Open your VPN app</b>" : "Traffic only goes through <b>utun4</b>.";
    $(".shield").textContent = down ? "!" : "✓";
    update();
  };
  toggle?.addEventListener("click", () => setVPN(!vpnDown));

  // MARK: Malware scan demo: scans when it scrolls into view, then flags the disguised file.
  const sheet = $("[data-scan]");
  if (sheet) {
    const flag = () => { sheet.classList.add("scanning"); setTimeout(() => sheet.classList.add("flagged"), reduced ? 0 : 1100); };
    if (reduced) flag();
    else new IntersectionObserver(([e], o) => { if (e.isIntersecting) { flag(); o.disconnect(); } }, { threshold: 0.5 }).observe(sheet);
    $("[data-skip]")?.addEventListener("click", (e) => {
      $("[data-bad]").classList.add("skipped");
      e.target.textContent = "Skipped";
      e.target.disabled = true;
    });
  }

  // MARK: Theme chips restyle both demo windows.
  const setTheme = (name) => {
    ["#app", "#mini"].forEach((id) => $(id)?.setAttribute("data-theme", name));
    $$("[data-theme-pick]").forEach((b) => b.setAttribute("aria-checked", String(b.dataset.themePick === name)));
  };
  $$("[data-theme-pick]").forEach((b) => b.addEventListener("click", () => setTheme(b.dataset.themePick)));
  if (params.get("theme")) setTheme(params.get("theme"));

  // MARK: Count-up numbers.
  const counters = $$("[data-count]");
  const countUp = (el) => {
    const target = +el.dataset.count;
    if (reduced || target === 0) { el.textContent = target; return; }
    const start = performance.now();
    const tick = (now) => {
      const t = Math.min(1, (now - start) / 1400);
      el.textContent = Math.round(target * (1 - Math.pow(1 - t, 3)));
      if (t < 1) requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  };
  const co = new IntersectionObserver((entries) => entries.forEach((e) => { if (e.isIntersecting) { countUp(e.target); co.unobserve(e.target); } }));
  counters.forEach((el) => co.observe(el));
})();
