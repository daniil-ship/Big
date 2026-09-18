/* ═══════════════════════════════════════════════════════════
   GOOGLE REMADE ×100000 — Liquid Glass Edition · app.js
   ═══════════════════════════════════════════════════════════ */
"use strict";

const $  = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];

/* ───────────────────────── I18N ───────────────────────── */
const I18N = {
  ru: {
    navAbout: "О Google", navStore: "Магазин", navMail: "Почта", navImages: "Картинки",
    badge: "ремейк · лучше в ×100 000",
    phSearch: "Ищите в Google — как в 2026",
    btnSearch: "Искать в Google", btnLucky: "Мне повезёт!",
    trending: "Сейчас ищут",
    appMail: "Почта", appMaps: "Карты", appDrive: "Диск", appPhotos: "Фото",
    appTranslate: "Переводчик", appCalendar: "Календарь",
    hint: "— быстрый фокус ·", hint2: "— поиск",
    footAds: "Реклама", footBusiness: "Для бизнеса", footHow: "Как работает Поиск",
    footMade: "сделано из жидкого стекла", footPrivacy: "Конфиденциальность", footTerms: "Условия",
    toastParty: "Теперь ещё в 100000 раз лучше 🎉",
    listening: "Говорите…",
    voiceOff: "Голосовой поиск недоступен в этом браузере",
    suggRecent: "Недавние запросы",
    suggNo: "Ничего не нашлось — жми Enter, Google разберётся",
    chips: [
      { icon: "🌦", label: "Погода",        q: "погода сейчас",        c: "#00E5FF" },
      { icon: "📰", label: "Новости",       q: "главные новости",      c: "#4285F4" },
      { icon: "💱", label: "Курс валют",    q: "курс доллара сегодня", c: "#34A853" },
      { icon: "🎬", label: "Что посмотреть",q: "что посмотреть вечером", c: "#EA4335" },
      { icon: "⚽", label: "Спорт",         q: "спорт результаты",     c: "#FBBC05" },
      { icon: "🚀", label: "Космос",        q: "последние новости космоса", c: "#7C4DFF" },
    ],
  },
  en: {
    navAbout: "About", navStore: "Store", navMail: "Gmail", navImages: "Images",
    badge: "remade · ×100,000 better",
    phSearch: "Search Google — like it's 2026",
    btnSearch: "Google Search", btnLucky: "I'm Feeling Lucky",
    trending: "Trending",
    appMail: "Gmail", appMaps: "Maps", appDrive: "Drive", appPhotos: "Photos",
    appTranslate: "Translate", appCalendar: "Calendar",
    hint: "to focus ·", hint2: "to search",
    footAds: "Advertising", footBusiness: "Business", footHow: "How Search works",
    footMade: "made of liquid glass", footPrivacy: "Privacy", footTerms: "Terms",
    toastParty: "Now even ×100000 better 🎉",
    listening: "Listening…",
    voiceOff: "Voice search isn't available in this browser",
    suggRecent: "Recent searches",
    suggNo: "Nothing here — hit Enter, Google will figure it out",
    chips: [
      { icon: "🌦", label: "Weather",  q: "weather now",        c: "#00E5FF" },
      { icon: "📰", label: "News",     q: "top news today",     c: "#4285F4" },
      { icon: "💱", label: "USD rate", q: "usd exchange rate",  c: "#34A853" },
      { icon: "🎬", label: "Movies",   q: "what to watch tonight", c: "#EA4335" },
      { icon: "⚽", label: "Sports",   q: "sports results",     c: "#FBBC05" },
      { icon: "🚀", label: "Space",    q: "latest space news",  c: "#7C4DFF" },
    ],
  },
};

const store = {
  get(k, d) { try { const v = localStorage.getItem(k); return v === null ? d : JSON.parse(v); } catch { return d; } },
  set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch { /* noop */ } },
};

let lang  = store.get("gr_lang", "ru");
let theme = store.get("gr_theme", "dark");
const T = () => I18N[lang];

/* ───────────────────────── ТЕМА ───────────────────────── */
const metaTheme = $('meta[name="theme-color"]');
function applyTheme() {
  document.documentElement.dataset.theme = theme;
  metaTheme.content = theme === "dark" ? "#0b0d12" : "#edf1f8";
}
$("#themeBtn").addEventListener("click", () => {
  theme = theme === "dark" ? "light" : "dark";
  store.set("gr_theme", theme);
  applyTheme();
});

/* ───────────────────────── ЯЗЫК ───────────────────────── */
function applyLang() {
  const d = T();
  document.documentElement.lang = lang;
  document.title = lang === "ru" ? "Google — но в 100000 раз лучше" : "Google — but ×100000 better";
  $$("[data-i18n]").forEach(el => { const k = el.dataset.i18n; if (d[k] != null) el.textContent = d[k]; });
  $$("[data-i18n-ph]").forEach(el => { const k = el.dataset.i18nPh; if (d[k] != null) el.placeholder = d[k]; });
  $("#langLabel").textContent = lang.toUpperCase();
  renderChips();
}
$("#langBtn").addEventListener("click", () => {
  lang = lang === "ru" ? "en" : "ru";
  store.set("gr_lang", lang);
  applyLang();
});

/* ───────────────────── БЛИК ЗА КУРСОРОМ ───────────────────── */
$$(".glare").forEach(el => {
  const light = document.createElement("span");
  light.className = "glare-light";
  light.setAttribute("aria-hidden", "true");
  el.prepend(light);
  el.addEventListener("pointermove", e => {
    const r = el.getBoundingClientRect();
    el.style.setProperty("--gx", `${e.clientX - r.left}px`);
    el.style.setProperty("--gy", `${e.clientY - r.top}px`);
  });
});

/* ─────────────── БЛОБ, СЛЕДУЮЩИЙ ЗА МЫШЬЮ ─────────────── */
const mouseBlob = $("#mouseBlob");
const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
if (!reducedMotion) {
  let tx = innerWidth / 2, ty = innerHeight * 0.4;
  let cx = tx, cy = ty;
  addEventListener("pointermove", e => { tx = e.clientX; ty = e.clientY; }, { passive: true });
  (function blobLoop() {
    cx += (tx - cx) * 0.045;
    cy += (ty - cy) * 0.045;
    mouseBlob.style.transform = `translate3d(${cx}px, ${cy}px, 0)`;
    requestAnimationFrame(blobLoop);
  })();
} else {
  mouseBlob.style.display = "none";
}

/* ───────────────────── ТРЕНДЫ-ЧИПСЫ ───────────────────── */
const chipsBox = $("#chips");
function renderChips() {
  chipsBox.innerHTML = "";
  T().chips.forEach((chip, i) => {
    const b = document.createElement("button");
    b.type = "button";
    b.className = "chip";
    b.style.setProperty("--chip-c", chip.c);
    b.style.animation = `fadeUp .5s var(--ease-out) ${0.05 * i}s backwards`;
    b.innerHTML = `<span>${chip.icon}</span><span>${chip.label}</span>`;
    b.addEventListener("click", () => doSearch(chip.q));
    chipsBox.append(b);
  });
}

/* ────────────────────── ПОИСК ────────────────────── */
const form  = $("#searchForm");
const input = $("#q");

const isURL = s => !/\s/.test(s) && /^([a-z0-9-]+\.)+[a-z]{2,}(\/\S*)?$/i.test(s);

function shake() {
  form.classList.remove("shake");
  void form.offsetWidth;
  form.classList.add("shake");
}

function pushHistory(q) {
  const h = store.get("gr_history", []).filter(x => x.toLowerCase() !== q.toLowerCase());
  h.unshift(q);
  store.set("gr_history", h.slice(0, 8));
}

function doSearch(q) {
  q = (q ?? input.value).trim();
  if (!q) { shake(); input.focus(); return; }
  pushHistory(q);
  if (isURL(q)) {
    location.href = /^https?:\/\//i.test(q) ? q : "https://" + q;
  } else {
    location.href = "https://www.google.com/search?q=" + encodeURIComponent(q) + "&hl=" + lang;
  }
}

form.addEventListener("submit", e => { e.preventDefault(); doSearch(); });
$("#btnSearch").addEventListener("click", () => doSearch());
$("#btnLucky").addEventListener("click", e => {
  const q = input.value.trim();
  const r = e.currentTarget.getBoundingClientRect();
  burst(r.left + r.width / 2, r.top + r.height / 2, 110);

  if (q) doSearch(q);
  else location.href = "https://doodles.google";
});

/* фон оживает при фокусе */
input.addEventListener("focus", () => document.body.classList.add("searching"));
input.addEventListener("blur",  () => document.body.classList.remove("searching"));

/* ──────────────── ПОДСКАЗКИ (история + live) ──────────────── */
const suggestBox = $("#suggest");
let sugItems = [];        // [{text, type}]
let activeIdx = -1;
let ddgToken = 0;
let debounceTimer = 0;

const ICON_CLOCK = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/></svg>`;
const ICON_SEARCH = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.8-3.8"/></svg>`;

function escapeHtml(s) {
  return s.replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

function highlight(text, query) {
  const i = text.toLowerCase().indexOf(query.toLowerCase());
  if (i < 0 || !query) return escapeHtml(text);
  return escapeHtml(text.slice(0, i)) + `<span class="hl">` + escapeHtml(text.slice(i, i + query.length)) + `</span>` + escapeHtml(text.slice(i + query.length));
}

function closeSuggest() {
  suggestBox.classList.remove("open");
  activeIdx = -1;
}

function renderSuggest(items, query, showHeader) {
  sugItems = items;
  activeIdx = -1;
  if (!items.length) {
    suggestBox.innerHTML = `<div class="suggest-empty">${ICON_SEARCH}<span>${T().suggNo}</span></div>`;
  } else {
    let html = "";
    if (showHeader) html += `<div class="suggest-empty" style="padding-bottom:6px">${ICON_CLOCK}<span>${T().suggRecent}</span></div>`;
    html += items.map((it, i) => `
      <div class="suggest-item" role="option" data-i="${i}" style="--d:${i * 35}ms">
        ${it.type === "hist" ? ICON_CLOCK : ICON_SEARCH}
        <span>${highlight(it.text, query || "")}</span>
        ${it.type === "hist" ? `<button type="button" class="remove" data-del="${i}" aria-label="Удалить">✕</button>` : ""}
      </div>`).join("");
    suggestBox.innerHTML = html;

    $$(".suggest-item", suggestBox).forEach(el => {
      el.addEventListener("mousedown", e => {
        if (e.target.closest(".remove")) return;
        e.preventDefault();
        const it = sugItems[+el.dataset.i];
        input.value = it.text;
        doSearch(it.text);
      });
    });
    $$(".remove", suggestBox).forEach(btn => {
      btn.addEventListener("mousedown", e => {
        e.preventDefault();
        e.stopPropagation();
        const it = sugItems[+btn.dataset.del];
        store.set("gr_history", store.get("gr_history", []).filter(x => x !== it.text));
        refreshSuggest();
      });
    });
  }
  suggestBox.classList.add("open");
}

function refreshSuggest() {
  const q = input.value.trim();
  const hist = store.get("gr_history", []);

  if (!q) {
    if (hist.length) renderSuggest(hist.slice(0, 6).map(t => ({ text: t, type: "hist" })), "", true);
    else closeSuggest();
    return;
  }

  const local = hist.filter(h => h.toLowerCase().includes(q.toLowerCase()) && h.toLowerCase() !== q.toLowerCase())
                    .slice(0, 2)
                    .map(t => ({ text: t, type: "hist" }));

  // live-подсказки через DuckDuckGo JSONP (с защитой от гонок)
  const token = ++ddgToken;
  const cbName = "__grcb" + token;
  window[cbName] = data => {
    delete window[cbName];
    script.remove();
    if (token !== ddgToken) return; // устарел
    const phrases = (Array.isArray(data) ? data : [])
      .map(d => (d && (d.phrase || d.q || d)) )
      .filter(x => typeof x === "string")
      .filter(x => x.toLowerCase() !== q.toLowerCase())
      .slice(0, 8 - local.length)
      .map(t => ({ text: t, type: "sugg" }));
    renderSuggest([...local, ...phrases], q, false);
  };
  const script = document.createElement("script");
  script.src = `https://duckduckgo.com/ac/?type=list&kl=${lang === "ru" ? "ru-ru" : "us-en"}&q=${encodeURIComponent(q)}&callback=${cbName}`;
  script.onerror = () => {
    delete window[cbName];
    if (token === ddgToken) renderSuggest(local, q, local.length > 0);
  };
  document.head.append(script);
}

input.addEventListener("input", () => {
  clearTimeout(debounceTimer);
  debounceTimer = setTimeout(refreshSuggest, 160);
});
input.addEventListener("focus", () => {
  clearTimeout(debounceTimer);
  refreshSuggest();
  setTimeout(() => input.setSelectionRange(input.value.length, input.value.length), 0);
});
document.addEventListener("mousedown", e => {
  if (!form.contains(e.target)) closeSuggest();
});

input.addEventListener("keydown", e => {
  const open = suggestBox.classList.contains("open");
  if (e.key === "ArrowDown" || e.key === "ArrowUp") {
    if (!open || !sugItems.length) return;
    e.preventDefault();
    const dir = e.key === "ArrowDown" ? 1 : -1;
    activeIdx = (activeIdx + dir + sugItems.length) % sugItems.length;
    $$(".suggest-item", suggestBox).forEach((el, i) => el.classList.toggle("active", i === activeIdx));
    input.value = sugItems[activeIdx].text;
  } else if (e.key === "Enter") {
    if (open && activeIdx >= 0) { e.preventDefault(); doSearch(sugItems[activeIdx].text); }
    closeSuggest();
  } else if (e.key === "Escape") {
    input.value = "";
    closeSuggest();
    input.blur();
  } else if (e.key === "Tab" && open) {
    closeSuggest();
  }
});

/* шорткат « / » — фокус на поиск */
document.addEventListener("keydown", e => {
  if (e.key === "/" && document.activeElement !== input && !e.metaKey && !e.ctrlKey) {
    e.preventDefault();
    input.focus();
  }
});

/* ──────────────── ГОЛОСОВОЙ ПОИСК ──────────────── */
const micBtn = $("#micBtn");
const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
if (SR) {
  const rec = new SR();
  rec.interimResults = true;
  rec.maxAlternatives = 1;
  let listening = false;

  micBtn.addEventListener("click", () => {
    if (listening) { rec.stop(); return; }
    try {
      rec.lang = lang === "ru" ? "ru-RU" : "en-US";
      rec.start();
    } catch { /* уже запущен */ }
  });

  rec.addEventListener("start", () => {
    listening = true;
    micBtn.classList.add("listening");
    input.placeholder = T().listening;
    input.focus();
  });
  rec.addEventListener("result", e => {
    let final = "", interim = "";
    for (const r of e.results) (r.isFinal ? final += r[0].transcript : interim += r[0].transcript);
    input.value = final || interim;
    if (final) { rec.stop(); doSearch(final); }
  });
  const stop = () => {
    listening = false;
    micBtn.classList.remove("listening");
    applyLang(); // вернуть обычный плейсхолдер
  };
  rec.addEventListener("end", stop);
  rec.addEventListener("error", stop);
} else {
  micBtn.addEventListener("click", () => toast(T().voiceOff));
}

/* lens — открываем Google Lens */
$("#lensBtn").addEventListener("click", () => {
  window.open("https://lens.google.com", "_blank", "noopener");
});

/* иконка приложений → подсветка плиток */
$("#appsBtn").addEventListener("click", () => {
  const apps = $("#apps");
  apps.scrollIntoView({ behavior: "smooth", block: "center" });
  $$(".tile", apps).forEach((t, i) => {
    setTimeout(() => {
      t.animate(
        [{ transform: "scale(1)" }, { transform: "scale(1.14) rotate(4deg)" }, { transform: "scale(1)" }],
        { duration: 550, easing: "cubic-bezier(.34,1.56,.64,1)" }
      );
    }, i * 70);
  });
});

/* ────────────────── ТОСТ + КОНФЕТТИ ────────────────── */
const toastEl = $("#toast");
let toastTimer = 0;
function toast(msg) {
  toastEl.textContent = msg;
  toastEl.classList.add("show");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toastEl.classList.remove("show"), 2500);
}

const canvas = $("#confetti");
const ctx = canvas.getContext("2d");
const PALETTE = ["#4285F4", "#EA4335", "#FBBC05", "#34A853", "#7C4DFF", "#00E5FF", "#ffffff"];
let parts = [];
let rafId = 0;

function sizeCanvas() {
  canvas.width = innerWidth * devicePixelRatio;
  canvas.height = innerHeight * devicePixelRatio;
  ctx.setTransform(devicePixelRatio, 0, 0, devicePixelRatio, 0, 0);
}
sizeCanvas();
addEventListener("resize", sizeCanvas);

function burst(x, y, n = 140) {
  for (let i = 0; i < n; i++) {
    const a = Math.random() * Math.PI * 2;
    const sp = 4 + Math.random() * 11;
    parts.push({
      x, y,
      vx: Math.cos(a) * sp,
      vy: Math.sin(a) * sp - 5,
      g: 0.28,
      s: 3 + Math.random() * 5,
      c: PALETTE[(Math.random() * PALETTE.length) | 0],
      rot: Math.random() * Math.PI,
      vr: (Math.random() - 0.5) * 0.3,
      life: 90 + Math.random() * 50,
      round: Math.random() > 0.5,
    });
  }
  if (!rafId) confettiLoop();
}

function confettiLoop() {
  rafId = requestAnimationFrame(confettiLoop);
  ctx.clearRect(0, 0, innerWidth, innerHeight);
  parts = parts.filter(p => p.life > 0 && p.y < innerHeight + 40);
  if (!parts.length) {
    cancelAnimationFrame(rafId);
    rafId = 0;
    ctx.clearRect(0, 0, innerWidth, innerHeight);
    return;
  }
  for (const p of parts) {
    p.vy += p.g; p.x += p.vx; p.y += p.vy; p.rot += p.vr; p.life--;
    p.vx *= 0.99;
    ctx.save();
    ctx.translate(p.x, p.y);
    ctx.rotate(p.rot);
    ctx.globalAlpha = Math.min(1, p.life / 30);
    ctx.fillStyle = p.c;
    if (p.round) { ctx.beginPath(); ctx.arc(0, 0, p.s / 2, 0, Math.PI * 2); ctx.fill(); }
    else ctx.fillRect(-p.s / 2, -p.s / 2, p.s, p.s * 1.6);
    ctx.restore();
  }
}

/* пасхалка на бейдже */
const badge = $("#badge");
badge.addEventListener("click", () => {
  const r = badge.getBoundingClientRect();
  burst(r.left + r.width / 2, r.top + r.height / 2, 160);
  toast(T().toastParty);
  document.body.classList.add("party");
  setTimeout(() => document.body.classList.remove("party"), 3500);
});

/* ────────────────── ИНИЦИАЛИЗАЦИЯ ────────────────── */
applyTheme();
applyLang();
setTimeout(() => input.focus({ preventScroll: true }), 350);
