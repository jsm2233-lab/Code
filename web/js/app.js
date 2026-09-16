// Composition root: builds everything once and wires it together.

import { Engine } from "./engine.js";
import { UI } from "./ui.js";
import { buildMap } from "./mapview.js";
import { prefs, requestPersistence } from "./store.js";
import { subPolyline, displayName, tileKey } from "./streets.js";
import { COMPLETION_THRESHOLD } from "./engine.js";

const settings = {
  fog: prefs.get("fog", true),
  showUncollected: prefs.get("showUncollected", true),
  follow: prefs.get("follow", true),
  onboarded: prefs.get("onboarded", false),
};

const engine = new Engine();
const parts = buildMap(document.getElementById("map"), engine, settings);
const ui = new UI(engine, settings, parts);
const { map, coverage, player } = parts;

let followedOnce = false;

boot();

async function boot() {
  requestPersistence();
  await engine.load();

  ui.renderHUD();
  renderActiveTab();
  coverage.redraw();

  wireTabs();
  wireMap();
  wireControls();
  wireEngine();
  wireCelebrations();
  wireDelegatedActions();

  if (!settings.onboarded) showOnboarding();
  else locateOnce();

  if ("serviceWorker" in navigator) {
    // Registered after first paint so it never delays the map appearing.
    window.addEventListener("load", () =>
      navigator.serviceWorker.register("./sw.js").catch(() => {})
    );
  }

  // Toasts expire on a timer rather than per-frame.
  setInterval(() => {
    if (engine.game.expireEvents()) ui.renderToasts();
  }, 1000);
}

// ---------- Wiring ----------

function wireTabs() {
  document.getElementById("tabbar").addEventListener("click", (event) => {
    const button = event.target.closest("button[data-tab]");
    if (!button) return;
    const tab = button.dataset.tab;
    ui.tab = tab;

    for (const node of document.querySelectorAll("#tabbar button")) {
      node.classList.toggle("active", node.dataset.tab === tab);
    }
    for (const screen of document.querySelectorAll(".screen")) {
      screen.classList.toggle("active", screen.dataset.screen === tab);
    }

    // Leaflet mismeasures itself if it was hidden when the window resized.
    if (tab === "map") setTimeout(() => map.invalidateSize(), 60);
    renderActiveTab();
  });
}

function wireMap() {
  map.on("moveend", () => {
    const bounds = map.getBounds();
    engine.loadTilesForBounds({
      south: bounds.getSouth(), west: bounds.getWest(),
      north: bounds.getNorth(), east: bounds.getEast(),
    });
  });

  // Tapping a street opens its detail sheet.
  map.on("click", (event) => {
    const point = { lat: event.latlng.lat, lon: event.latlng.lng };
    const candidates = engine.index.candidates(point, 40);
    if (!candidates.length) return;
    let best = null;
    let bestDistance = Infinity;
    for (const segment of candidates) {
      const d = perpendicularDistance(point, segment);
      if (d < bestDistance) {
        bestDistance = d;
        best = segment;
      }
    }
    if (best && bestDistance < 40) ui.showStreetSheet(best);
  });

  // Panning away should stop the map yanking back to the player.
  map.on("dragstart", () => {
    settings.follow = false;
    prefs.set("follow", false);
  });
}

function wireControls() {
  document.getElementById("btn-trip").addEventListener("click", async () => {
    if (navigator.vibrate) navigator.vibrate(10);
    await engine.toggleTrip();
    if (engine.activeTrip) {
      settings.follow = true;
      prefs.set("follow", true);
    }
    ui.renderHUD();
  });

  document.getElementById("btn-suggest").addEventListener("click", () => ui.showSuggestions());

  document.getElementById("btn-locate").addEventListener("click", () => {
    settings.follow = true;
    prefs.set("follow", true);
    if (engine.lastFix) map.setView([engine.lastFix.lat, engine.lastFix.lon], Math.max(map.getZoom(), 16));
    else locateOnce();
  });

  document.getElementById("sheet-backdrop").addEventListener("click", (event) => {
    if (event.target.id === "sheet-backdrop") ui.closeSheet();
  });

  document.getElementById("celebration").addEventListener("click", () => ui.hideCelebration());

  document.getElementById("street-search").addEventListener("input", (event) => {
    ui.streetSearch = event.target.value.trim();
    ui.renderStreets();
  });

  document.getElementById("street-filters").addEventListener("click", (event) => {
    const button = event.target.closest("button[data-filter]");
    if (!button) return;
    ui.streetFilter = button.dataset.filter;
    ui.renderStreets();
  });

  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") {
      engine.handleVisible();
      ui.renderHUD();
    } else {
      engine.flush();
    }
  });
}

function wireEngine() {
  engine.addEventListener("position", () => {
    const fix = engine.lastFix;
    if (!fix) return;

    player.setLatLng([fix.lat, fix.lon]);
    if (!map.hasLayer(player)) player.addTo(map);
    const element = player.getElement();
    if (element) element.classList.toggle("collecting", Boolean(engine.activeTrip));

    if (settings.follow) map.setView([fix.lat, fix.lon], Math.max(map.getZoom(), 16), { animate: true });

    ui.renderHUD();
    coverage.redraw();
  });

  engine.addEventListener("tiles", () => {
    coverage.redraw();
    if (ui.tab === "settings") ui.renderSettings();
  });

  engine.addEventListener("change", () => {
    ui.renderHUD();
    renderActiveTab();
    coverage.redraw();
  });

  engine.game.addEventListener("score", () => ui.renderToasts());
}

function wireCelebrations() {
  engine.game.addEventListener("celebrate", (event) => ui.showCelebration(event.detail));
}

/** One delegated listener for every button rendered into a screen, since those
 *  screens are re-rendered wholesale. */
function wireDelegatedActions() {
  document.addEventListener("click", async (event) => {
    const toggle = event.target.closest("[data-toggle]");
    if (toggle) {
      const key = toggle.dataset.toggle;
      settings[key] = !settings[key];
      prefs.set(key, settings[key]);
      toggle.classList.toggle("on", settings[key]);
      coverage.redraw();
      return;
    }

    const action = event.target.closest("[data-action]");
    if (!action) return;

    switch (action.dataset.action) {
      case "clear-tiles":
        await engine.clearStreetCache();
        ui.renderSettings();
        break;

      case "refresh-tile":
        await engine.refreshTile(action.dataset.tile);
        ui.closeSheet();
        coverage.redraw();
        break;

      case "export":
        exportGeoJSON();
        break;

      case "reset":
        if (confirm("Delete every collected street, trip and badge? This cannot be undone.")) {
          await engine.resetEverything();
          ui.renderHUD();
          renderActiveTab();
          coverage.redraw();
        }
        break;
    }
  });

  document.addEventListener("click", (event) => {
    if (event.target.id === "btn-export") exportGeoJSON();
  });
}

// ---------- Helpers ----------

function renderActiveTab() {
  switch (ui.tab) {
    case "streets": ui.renderStreets(); break;
    case "stats": ui.renderStats(); break;
    case "badges": ui.renderBadges(); break;
    case "settings": ui.renderSettings(); break;
    default: ui.renderHUD();
  }
}

function locateOnce() {
  if (!navigator.geolocation) return;
  navigator.geolocation.getCurrentPosition(
    (position) => {
      const { latitude, longitude } = position.coords;
      engine.lastFix = {
        lat: latitude, lon: longitude, accuracy: position.coords.accuracy,
        heading: -1, speed: -1, time: position.timestamp,
      };
      if (!followedOnce) {
        map.setView([latitude, longitude], 16);
        followedOnce = true;
      }
      player.setLatLng([latitude, longitude]).addTo(map);
      engine.game.setHomeTile(tileKey(latitude, longitude));
      engine.loadTiles([tileKey(latitude, longitude)]);
    },
    () => {},
    { enableHighAccuracy: true, timeout: 15000, maximumAge: 60000 }
  );
}

function perpendicularDistance(point, segment) {
  let best = Infinity;
  const points = segment.points;
  for (let i = 1; i < points.length; i++) {
    const a = points[i - 1];
    const b = points[i];
    const mLat = 111320;
    const mLon = 111320 * Math.cos((a.lat * Math.PI) / 180);
    const bx = (b.lon - a.lon) * mLon;
    const by = (b.lat - a.lat) * mLat;
    const px = (point.lon - a.lon) * mLon;
    const py = (point.lat - a.lat) * mLat;
    const lengthSquared = bx * bx + by * by;
    const t = lengthSquared > 0 ? Math.max(0, Math.min(1, (px * bx + py * by) / lengthSquared)) : 0;
    best = Math.min(best, Math.hypot(px - t * bx, py - t * by));
  }
  return best;
}

/** GeoJSON export, so the collection isn't trapped in one browser's storage. */
function exportGeoJSON() {
  const features = [];
  for (const [id, entry] of engine.coverage) {
    const segment = engine.index.get(id);
    if (!segment) continue;
    for (const [lower, upper] of entry.intervals) {
      const points = subPolyline(segment, lower, upper);
      if (points.length < 2) continue;
      features.push({
        type: "Feature",
        geometry: { type: "LineString", coordinates: points.map((p) => [p.lon, p.lat]) },
        properties: {
          name: displayName(segment),
          segment_id: id,
          class: segment.klass,
          complete: engine.fractionFor(id) >= COMPLETION_THRESHOLD,
          first_seen: new Date(entry.first).toISOString(),
          last_seen: new Date(entry.last).toISOString(),
        },
      });
    }
  }

  const blob = new Blob([JSON.stringify({ type: "FeatureCollection", features })], {
    type: "application/geo+json",
  });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = "street-collection.geojson";
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 5000);
}

// ---------- Onboarding ----------

function showOnboarding() {
  const root = document.getElementById("onboarding");
  const pages = [
    {
      glyph: "🌃",
      title: "Collect your city",
      body: "Every street you go down lights up and stays lit. The rest stays dark. The goal is simple and slightly unhinged: all of them.",
    },
    {
      glyph: "📍",
      title: "One catch",
      body: "Safari stops tracking the moment you leave this page or lock the screen. Keep it open and in front while you travel — the screen is held awake for you during a trip.",
      warn: "That's a browser limit, not a setting. A mounted phone on a drive or a walk with the app open works fine; pocketing it does not.",
    },
    {
      glyph: "🏅",
      title: "Levels, streaks, badges",
      body: "Backstreets pay more than motorway. Finish a street end to end for the bonus. Come back tomorrow to keep the streak alive.",
    },
  ];

  let index = 0;
  root.classList.remove("hidden");

  function draw() {
    const page = pages[index];
    const last = index === pages.length - 1;
    root.innerHTML = `
      <div class="orb">${page.glyph}</div>
      <h1>${page.title}</h1>
      <p>${page.body}</p>
      ${page.warn ? `<div class="warn">${page.warn}</div>` : ""}
      <div class="dots">${pages.map((_, i) => `<i class="${i === index ? "on" : ""}"></i>`).join("")}</div>
      <button class="primary-button" id="onboard-next">${last ? "Allow location and start" : "Next"}</button>`;

    document.getElementById("onboard-next").addEventListener("click", () => {
      if (!last) {
        index += 1;
        draw();
        return;
      }
      settings.onboarded = true;
      prefs.set("onboarded", true);
      root.classList.add("hidden");
      locateOnce();
    });
  }

  draw();
}
