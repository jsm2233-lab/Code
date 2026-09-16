// Screen rendering. Plain DOM: no framework, because the only genuinely hot
// view is the map canvas, and everything else redraws at human speed.

import * as F from "./format.js";
import { CLASS_INFO, displayName } from "./streets.js";
import { COMPLETION_THRESHOLD } from "./engine.js";
import { TIER_XP, levelTitle } from "./game.js";
import { burst } from "./confetti.js";
import { estimateUsage } from "./store.js";

const TIERS = ["legendary", "gold", "silver", "bronze"];
const MODE_ICON = { walking: "🚶", cycling: "🚲", driving: "🚗", unknown: "📍" };
const QUALITY_LABEL = {
  unknown: "Waiting for GPS",
  good: "Collecting",
  weak: "Weak signal",
  "off-road": "No street here",
};

export class UI {
  constructor(engine, settings, mapParts) {
    this.engine = engine;
    this.settings = settings;
    this.mapParts = mapParts;
    this.tab = "map";
    this.streetFilter = "all";
    this.streetSearch = "";
    this.dismissCelebration = null;
  }

  // ---------- HUD ----------

  renderHUD() {
    const engine = this.engine;
    const game = engine.game;
    const trip = engine.activeTrip;
    const running = Boolean(trip);

    const streak = game.profile.currentStreak > 0
      ? `<div class="streak">🔥<span>${game.profile.currentStreak}</span></div>`
      : "";

    const live = running
      ? `<div class="hud-live">
          <div class="live-stats">
            <div class="live-stat"><b>${F.distance(trip.distance)}</b><span>travelled</span></div>
            <div class="live-stat new"><b>${F.distance(trip.newStreetMetres)}</b><span>new</span></div>
            <div class="live-stat collected"><b>${trip.completedSegmentIDs.length}</b><span>collected</span></div>
            <div class="live-stat xp"><b>+${F.xp(trip.xp)}</b><span>xp</span></div>
          </div>
          <div class="live-status">
            <i class="dot ${engine.matchQuality}"></i>
            <span>${F.escape(
              engine.currentSegment ? displayName(engine.currentSegment) : QUALITY_LABEL[engine.matchQuality]
            )}</span>
          </div>
        </div>`
      : "";

    document.getElementById("hud").innerHTML = `
      <div class="panel ${running ? "panel--glow" : ""}">
        <div class="hud-top">
          <div class="level-badge">${F.ring(game.levelProgress, { size: 46, width: 4 })}<span>${game.level}</span></div>
          <div class="level-meta">
            <div class="level-row">
              <span class="level-title">${F.escape(levelTitle(game.level))}</span>
              <span class="level-xp">${F.xp(game.xpIntoLevel)}/${F.xp(game.xpForNextLevel)}</span>
            </div>
            <div class="bar"><span style="width:${(game.levelProgress * 100).toFixed(1)}%"></span></div>
          </div>
          ${streak}
        </div>
        ${live}
      </div>`;

    const button = document.getElementById("btn-trip");
    button.textContent = running ? "End trip" : "Start collecting";
    button.classList.toggle("running", running);
  }

  renderToasts() {
    const container = document.getElementById("toasts");
    const events = this.engine.game.recentEvents;
    container.innerHTML = events
      .map(
        (event) => `<div class="toast">
          <span class="icon">${event.icon}</span>
          <span class="name">${F.escape(event.title)}</span>
          <span class="xp">+${F.xp(event.xp)}</span>
        </div>`
      )
      .join("");
  }

  // ---------- Collection ----------

  renderStreets() {
    const filters = document.getElementById("street-filters");
    const options = [
      ["all", "All"],
      ["complete", "Collected"],
      ["partial", "In progress"],
    ];
    filters.innerHTML = options
      .map(([key, label]) => `<button data-filter="${key}" class="${this.streetFilter === key ? "active" : ""}">${label}</button>`)
      .join("");

    const list = document.getElementById("street-list");
    let streets = this.engine.collectedStreets();

    if (this.streetFilter === "complete") streets = streets.filter((s) => s.fullyCollected);
    if (this.streetFilter === "partial") streets = streets.filter((s) => !s.fullyCollected);
    if (this.streetSearch) {
      const needle = this.streetSearch.toLowerCase();
      streets = streets.filter((s) => s.name.toLowerCase().includes(needle));
    }

    if (!this.engine.touchedCount) {
      list.innerHTML = emptyState("🌃", "The city is dark", "Start a trip on the map. Every street you go down lands here, and stays.");
      return;
    }

    const summary = `<div class="tile-row">
      ${statTile("✅", this.engine.completedCount, "Collected", "")}
      ${statTile("◐", Math.max(0, this.engine.touchedCount - this.engine.completedCount), "In progress", "amber")}
    </div>`;

    const rows = streets
      .map((street) => {
        const complete = street.fullyCollected;
        const gradient = complete ? "ringGradient" : "ringAmber";
        return `<div class="card">
          <div class="street-row">
            <div class="street-ring">${F.ring(street.fraction, { size: 42, width: 4, gradient })}<span>${complete ? "✓" : "◐"}</span></div>
            <div class="street-meta">
              <div class="name">${F.escape(street.name)}</div>
              <div class="street-tags">
                <span class="chip">${F.escape(CLASS_INFO[street.klass].label)}</span>
                <span class="length">${F.distance(street.metresCovered)}</span>
              </div>
            </div>
            <div class="street-figures">
              <b style="color:${complete ? "var(--accent)" : "var(--partial)"}">${F.percent(street.fraction)}</b>
              <span>${F.relative(street.last)}</span>
            </div>
          </div>
        </div>`;
      })
      .join("");

    list.innerHTML = summary + (rows || `<p class="empty">Nothing matches.</p>`);
  }

  // ---------- Stats ----------

  renderStats() {
    const engine = this.engine;
    const game = engine.game;
    const profile = game.profile;

    const areas = [...engine.loadedTiles]
      .map((key) => engine.tileCompletion(key))
      .filter((completion) => completion.segments > 0)
      .sort((a, b) => b.fraction - a.fraction)
      .slice(0, 12);

    const areaGrid = areas.length
      ? `<div class="area-grid">${areas
          .map(
            (area) => `<div class="area">
              <div class="ring">${F.ring(area.fraction, {
                size: 48, width: 5, gradient: area.fraction >= 1 ? "ringViolet" : "ringGradient",
              })}<span>${Math.round(area.fraction * 100)}</span></div>
              <small>${area.completed}/${area.segments}</small>
            </div>`
          )
          .join("")}</div>`
      : `<p style="color:rgba(255,255,255,0.5);font-size:14px;margin:0">Move around to load street data for your area.</p>`;

    const daily = engine.dailyNewMetres(30);
    const chart = barChart(daily);

    const trips = engine.trips.slice(0, 5);
    const tripRows = trips.length
      ? trips
          .map(
            (trip) => `<div class="street-row" style="margin-bottom:14px">
              <div style="width:36px;height:36px;flex:0 0 36px;border-radius:11px;display:grid;place-items:center;background:linear-gradient(120deg,var(--accent),#36b8ff);font-size:16px">${MODE_ICON[trip.mode]}</div>
              <div class="street-meta">
                <div class="name" style="font-size:14px">${F.dateTime(trip.startedAt)}</div>
                <div class="length">${F.distance(trip.distance)} · ${F.distance(trip.newStreetMetres)} new · ${trip.completedSegmentIDs.length} collected</div>
              </div>
              <div class="street-figures"><b style="color:var(--accent);font-size:13px">+${F.xp(trip.xp)}</b></div>
            </div>`
          )
          .join("")
      : `<p style="color:rgba(255,255,255,0.5);font-size:14px;margin:0">Your finished trips show up here.</p>`;

    document.getElementById("stats-body").innerHTML = `
      <div class="card" style="border-color:rgba(45,224,165,0.35)">
        <div class="street-row" style="align-items:center">
          <div class="street-ring" style="width:86px;height:86px;flex:0 0 86px;font-size:11px">
            ${F.ring(game.levelProgress, { size: 86, width: 9 })}
            <span style="display:flex;flex-direction:column;align-items:center">
              <b style="font-size:32px;font-weight:800">${game.level}</b>
              <small style="font-size:8px;letter-spacing:0.2em;color:rgba(255,255,255,0.4)">LEVEL</small>
            </span>
          </div>
          <div class="street-meta" style="margin-left:6px">
            <div class="name" style="font-size:22px">${F.escape(levelTitle(game.level))}</div>
            <div style="color:var(--accent);font-weight:800;font-size:14px;margin-top:4px">${F.xp(profile.xp)} XP</div>
            <div class="bar" style="margin-top:8px"><span style="width:${(game.levelProgress * 100).toFixed(1)}%"></span></div>
            <div class="length" style="margin-top:6px">${F.xp(Math.max(0, game.xpForNextLevel - game.xpIntoLevel))} XP to level ${game.level + 1}</div>
          </div>
        </div>
        <div class="tile-row" style="margin:16px 0 0">
          <div class="stat-tile amber"><b>🔥 ${profile.currentStreak}</b><span>day streak</span></div>
          <div class="stat-tile"><b>🏆 ${profile.longestStreak}</b><span>best ever</span></div>
        </div>
      </div>

      <div class="card"><h2>Areas</h2>${areaGrid}</div>
      <div class="card"><h2>New streets, last 30 days</h2>${chart}</div>

      <div class="tile-row">
        ${statTile("✅", engine.completedCount, "Streets collected", "")}
        ${statTile("✨", F.distance(profile.totalNewStreetMetres), "New street distance", "amber")}
      </div>
      <div class="tile-row">
        ${statTile("➡️", F.distance(profile.totalDistance), "Total travelled", "cyan")}
        ${statTile("🚶", engine.trips.length, "Trips", "violet")}
      </div>

      <div class="card"><h2>Recent trips</h2>${tripRows}</div>
      <button class="primary-button" id="btn-export" style="width:100%;margin-top:4px">Export collection (GeoJSON)</button>`;
  }

  // ---------- Badges ----------

  renderBadges() {
    const game = this.engine.game;
    const progress = game.progressList(this.engine.stats());
    const unlocked = progress.filter((p) => p.unlocked).length;

    const groups = TIERS.map((tier) => {
      const items = progress.filter((p) => p.achievement.tier === tier);
      if (!items.length) return "";
      const done = items.filter((i) => i.unlocked).length;
      const colour = { bronze: "#d98c4a", silver: "#c3cdd9", gold: "#ffd75e", legendary: "#a86bf5" }[tier];

      const cards = items
        .map((item) => {
          const a = item.achievement;
          // Anything past three quarters shimmers: the "nearly there" nudge,
          // and it would be noise on everything.
          const close = !item.unlocked && item.fraction >= 0.75;
          return `<div class="card badge-card ${tier} ${item.unlocked ? "unlocked" : ""} ${close ? "close" : ""}">
            <div class="medal">${a.icon}</div>
            <div class="badge-body">
              <div class="badge-head">
                <b>${F.escape(a.title)}</b>
                <span class="reward">+${F.xp(TIER_XP[tier])}</span>
              </div>
              <p>${F.escape(a.detail)}</p>
              ${
                item.unlocked
                  ? `<div style="color:${colour};font-size:11px;font-weight:800">✓ Unlocked</div>`
                  : `<div class="bar"><span style="width:${(item.fraction * 100).toFixed(1)}%;background:${colour};box-shadow:none"></span></div>
                     <div class="badge-progress">${progressLabel(item)}</div>`
              }
            </div>
          </div>`;
        })
        .join("");

      return `<div class="tier-heading" style="color:${colour}">
          <span>${tier}</span><i class="rule"></i><span class="count">${done}/${items.length}</span>
        </div>${cards}`;
    }).join("");

    document.getElementById("badges-body").innerHTML = `
      <div class="card" style="border-color:rgba(168,107,245,0.35)">
        <div class="street-row">
          <div class="street-ring" style="width:76px;height:76px;flex:0 0 76px">
            ${F.ring(progress.length ? unlocked / progress.length : 0, { size: 76, width: 7, gradient: "ringViolet" })}
            <span style="display:flex;flex-direction:column;align-items:center">
              <b style="font-size:24px;font-weight:800">${unlocked}</b>
              <small style="font-size:9px;color:rgba(255,255,255,0.4)">of ${progress.length}</small>
            </span>
          </div>
          <div class="street-meta">
            <div class="name" style="font-size:20px">Badge case</div>
            <p style="margin:6px 0 0;font-size:12px;color:rgba(255,255,255,0.5)">Each one pays a lump of XP the moment it unlocks. Progress counts everything you've already collected.</p>
          </div>
        </div>
      </div>
      ${groups}`;
  }

  // ---------- Settings ----------

  async renderSettings() {
    const engine = this.engine;
    const settings = this.settings;
    const usage = await estimateUsage();
    const usageLabel = usage && usage.usage ? `${(usage.usage / 1048576).toFixed(1)} MB` : "unknown";

    document.getElementById("settings-body").innerHTML = `
      <div class="banner">
        <b>Background collection isn't possible on the web.</b><br>
        iOS stops sending positions the moment you leave the app or lock the
        screen. Keep this page open and in front while you travel; the screen is
        held awake for you during a trip.
      </div>

      <div class="card">
        <h2>Map</h2>
        ${toggleRow("fog", "Fog of war", settings.fog)}
        ${toggleRow("showUncollected", "Show uncollected streets", settings.showUncollected)}
        ${toggleRow("follow", "Follow me while collecting", settings.follow)}
      </div>

      <div class="card">
        <h2>Street data</h2>
        <div class="setting"><span class="label">Loaded areas</span><span class="value">${engine.loadedTiles.size}</span></div>
        <div class="setting"><span class="label">Segments in memory</span><span class="value">${engine.index.size.toLocaleString()}</span></div>
        <div class="setting"><span class="label">Stored on device</span><span class="value">${usageLabel}</span></div>
        <div class="setting"><button class="label" style="text-align:left" data-action="clear-tiles">Clear downloaded street data</button></div>
        <p style="font-size:12px;color:rgba(255,255,255,0.4);margin:8px 0 0">
          Street geometry comes from OpenStreetMap contributors via the Overpass
          API. Clearing keeps your collection — only the maps are refetched.
        </p>
      </div>

      <div class="card">
        <h2>Data</h2>
        <div class="setting"><button class="label" style="text-align:left" data-action="export">Export collection (GeoJSON)</button></div>
        <div class="setting"><button class="label danger" style="text-align:left" data-action="reset">Reset all progress</button></div>
        <p style="font-size:12px;color:rgba(255,255,255,0.4);margin:8px 0 0">
          Everything is stored on this device only. Nothing is uploaded, and
          clearing Safari's website data deletes it.
        </p>
      </div>

      <div class="card">
        <h2>About</h2>
        <div class="setting"><span class="label">Version</span><span class="value">1.0 (web)</span></div>
        <div class="setting"><a class="label" style="color:var(--accent);text-decoration:none" href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap copyright</a></div>
      </div>`;
  }

  // ---------- Sheets ----------

  openSheet(html) {
    document.getElementById("sheet").innerHTML = `<div class="sheet-grabber"></div>${html}`;
    document.getElementById("sheet-backdrop").classList.add("open");
  }

  closeSheet() {
    document.getElementById("sheet-backdrop").classList.remove("open");
  }

  showStreetSheet(segment) {
    const entry = this.engine.coverage.get(segment.id);
    const fraction = this.engine.fractionFor(segment.id);
    const complete = fraction >= COMPLETION_THRESHOLD;
    const info = CLASS_INFO[segment.klass];

    this.openSheet(`
      <h3>${F.escape(displayName(segment))}</h3>
      <span class="chip">${F.escape(info.label)}</span>
      <div class="card" style="margin-top:16px">
        <div class="street-row">
          <div class="street-ring" style="width:78px;height:78px;flex:0 0 78px;font-size:15px">
            ${F.ring(fraction, { size: 78, width: 8, gradient: complete ? "ringGradient" : "ringAmber" })}
            <span>${F.percent(fraction)}</span>
          </div>
          <div class="street-meta">
            <div class="name" style="color:${complete ? "var(--accent)" : "var(--partial)"}">
              ${entry ? (complete ? "Collected" : "Partly collected") : "Not collected"}
            </div>
            <div class="length" style="margin-top:6px">${F.distance(fraction * segment.length)} of ${F.distance(segment.length)}</div>
            ${entry ? `<div class="length">Last seen ${F.relative(entry.last)}</div>` : ""}
          </div>
        </div>
      </div>
      <div class="card">
        <h2>Details</h2>
        ${detailRow("Type", info.label)}
        ${detailRow("Length", F.distance(segment.length))}
        ${detailRow("Direction", segment.oneway ? "One way" : "Two way")}
        ${detailRow("XP multiplier", `${info.multiplier.toFixed(1)}x`)}
        ${entry ? detailRow("First collected", F.dateTime(entry.first)) : ""}
        ${info.counts ? "" : `<p style="font-size:12px;color:rgba(255,255,255,0.4);margin:8px 0 0">Collectible, but doesn't count toward city completion.</p>`}
      </div>
      <button class="label" data-action="refresh-tile" data-tile="${segment.tile}"
              style="color:rgba(255,255,255,0.45);font-size:13px">↻ Street data looks wrong — refresh this area</button>`);
  }

  showSuggestions() {
    const fix = this.engine.lastFix;
    if (!fix) {
      this.openSheet(`<h3>Collect next</h3>${emptyState("📡", "No position yet", "Start a trip so the app knows where you are.")}`);
      return;
    }

    const suggestions = this.engine.suggestions({ lat: fix.lat, lon: fix.lon });
    const body = suggestions.length
      ? suggestions
          .map(
            (item) => `<div class="card">
              <div class="street-row">
                <div style="font-size:18px;flex:0 0 24px;color:${item.fraction > 0 ? "var(--partial)" : "var(--muted)"}">${item.fraction > 0 ? "◐" : "○"}</div>
                <div class="street-meta">
                  <div class="name" style="font-size:14px">${F.escape(displayName(item.segment))}</div>
                  <div class="length">${F.distance(item.distance)} away · ${F.distance(item.segment.length)} long</div>
                </div>
                ${item.fraction > 0 ? `<div class="street-figures"><b style="color:var(--partial);font-size:13px">${F.percent(item.fraction)}</b></div>` : ""}
              </div>
            </div>`
          )
          .join("")
      : emptyState("🏁", "Nothing left nearby", "Every street within a kilometre is collected, or street data hasn't loaded yet. Go further out.");

    this.openSheet(`<h3>Collect next</h3>${body}`);
  }

  // ---------- Celebration ----------

  showCelebration(detail) {
    const card = document.getElementById("celebration-card");
    const overlay = document.getElementById("celebration");

    if (detail.kind === "level") {
      card.innerHTML = `
        <div class="celebration-medal">${detail.level}</div>
        <div class="eyebrow">Level up</div>
        <h2>${F.escape(detail.title)}</h2>
        <p>You've reached level ${detail.level}.</p>
        <div class="hint">Tap to carry on</div>`;
    } else {
      const a = detail.achievement;
      const gradient = {
        bronze: "linear-gradient(135deg,#d98c4a,#9c5a24)",
        silver: "linear-gradient(135deg,#d6dee8,#8c9aab)",
        gold: "linear-gradient(135deg,#ffd75e,#f0921e)",
        legendary: "linear-gradient(135deg,#a86bf5,#ff5da2)",
      }[a.tier];
      card.innerHTML = `
        <div class="celebration-medal" style="background:${gradient}">${a.icon}</div>
        <div class="eyebrow">${a.tier} badge</div>
        <h2>${F.escape(a.title)}</h2>
        <p>${F.escape(a.detail)}</p>
        <div class="hint">Tap to carry on</div>`;
    }

    overlay.classList.add("open");
    if (navigator.vibrate) navigator.vibrate([12, 40, 18]);

    const stop = burst(document.getElementById("confetti"));
    clearTimeout(this._celebrationTimer);
    // Auto-dismissing matters: this fires while people are moving, so it must
    // never be something you have to deal with.
    this._celebrationTimer = setTimeout(() => this.hideCelebration(), 4500);
    this.dismissCelebration = () => {
      stop();
      overlay.classList.remove("open");
    };
  }

  hideCelebration() {
    clearTimeout(this._celebrationTimer);
    this.dismissCelebration?.();
    this.dismissCelebration = null;
  }
}

// ---------- Fragments ----------

/**
 * Bar chart as inline SVG with an explicit viewBox.
 *
 * The first version used flex children with percentage heights, and the
 * container resolved its flex basis from content rather than its own width, so
 * thirty thin bars came out as seven fat ones. An SVG with a fixed coordinate
 * space cannot be knocked over by whatever layout context it lands in.
 */
function barChart(daily) {
  if (daily.every((d) => d.metres === 0)) {
    return `<p style="color:rgba(255,255,255,0.5);font-size:14px;margin:0">No trips yet.</p>`;
  }

  const width = 300;
  const height = 110;
  const gap = 2;
  const barWidth = (width - gap * (daily.length - 1)) / daily.length;
  const peak = Math.max(1, ...daily.map((d) => d.metres));

  const bars = daily
    .map((day, index) => {
      const barHeight = day.metres ? Math.max(2, (day.metres / peak) * height) : 2;
      const x = index * (barWidth + gap);
      const fill = day.metres ? "url(#chartFill)" : "rgba(255,255,255,0.07)";
      return `<rect x="${x.toFixed(2)}" y="${(height - barHeight).toFixed(2)}"
        width="${barWidth.toFixed(2)}" height="${barHeight.toFixed(2)}" rx="1.5" fill="${fill}"/>`;
    })
    .join("");

  return `<svg viewBox="0 0 ${width} ${height + 8}" width="100%" height="130" preserveAspectRatio="none"
               role="img" aria-label="New street distance per day over the last 30 days">
    <defs>
      <linearGradient id="chartFill" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0%" stop-color="#2de0a5"/>
        <stop offset="100%" stop-color="rgba(54,184,255,0.45)"/>
      </linearGradient>
    </defs>
    ${bars}
    <line x1="0" y1="${height + 1}" x2="${width}" y2="${height + 1}" stroke="rgba(255,255,255,0.1)" stroke-width="1"/>
  </svg>`;
}

function statTile(glyph, value, label, variant) {
  return `<div class="stat-tile ${variant}"><div class="glyph">${glyph}</div><b>${value}</b><span>${label}</span></div>`;
}

function detailRow(key, value) {
  return `<div class="detail-row"><span class="k">${F.escape(key)}</span><span class="v">${F.escape(value)}</span></div>`;
}

function toggleRow(key, label, on) {
  return `<div class="setting">
    <span class="label">${label}</span>
    <button class="switch ${on ? "on" : ""}" data-toggle="${key}" aria-label="${label}"></button>
  </div>`;
}

function emptyState(glyph, title, message) {
  return `<div class="empty"><div class="glyph">${glyph}</div><h3>${title}</h3><p>${message}</p></div>`;
}

function progressLabel(item) {
  const { value, achievement } = item;
  switch (achievement.kind) {
    case "newKm":
    case "tripNewKm":
    case "walkKm":
      return `${value.toFixed(1)} / ${achievement.target} km`;
    case "tile":
      return `${Math.round(value)}% / ${achievement.target}% of an area`;
    case "streak":
      return `${Math.round(value)} / ${achievement.target} days`;
    default:
      return `${Math.round(value)} / ${achievement.target}`;
  }
}
