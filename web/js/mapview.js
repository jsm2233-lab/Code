// Leaflet map plus the neon coverage canvas. Ports CoverageOverlay.swift.

import { subPolyline } from "./streets.js";
import { coveredFraction } from "./intervals.js";
import { COMPLETION_THRESHOLD } from "./engine.js";

// Signal colours, matching the CSS custom properties exactly.
const INK = {
  collected: "45, 224, 165",
  partial: "255, 188, 61",
  hot: "91, 200, 255",
  uncollected: "107, 122, 140",
};

// Above this many segments in view, uncollected streets stop being drawn: past
// that zoom they're a grey smear anyway, and redrawing them is what makes a
// map feel cheap.
const UNCOLLECTED_DRAW_LIMIT = 4000;

/**
 * One canvas for the whole collection, redrawn per frame from the spatial
 * index. One Leaflet polyline per segment would mean tens of thousands of DOM
 * or canvas paths tracked individually, which Leaflet does not enjoy.
 */
export function createCoverageLayer(engine, settings) {
  return L.Layer.extend({
    onAdd(map) {
      this._map = map;
      this._canvas = L.DomUtil.create("canvas", "sc-coverage-canvas");
      this._ctx = this._canvas.getContext("2d");
      map.getPanes().overlayPane.appendChild(this._canvas);
      map.on("move zoom resize viewreset zoomend moveend", this._reset, this);
      this._reset();
    },

    onRemove(map) {
      map.off("move zoom resize viewreset zoomend moveend", this._reset, this);
      this._canvas.remove();
    },

    redraw() {
      this._scheduleDraw();
    },

    _reset() {
      const map = this._map;
      if (!map) return;
      const size = map.getSize();
      const dpr = window.devicePixelRatio || 1;

      if (this._canvas.width !== size.x * dpr || this._canvas.height !== size.y * dpr) {
        this._canvas.width = size.x * dpr;
        this._canvas.height = size.y * dpr;
        this._canvas.style.width = `${size.x}px`;
        this._canvas.style.height = `${size.y}px`;
      }
      L.DomUtil.setPosition(this._canvas, map.containerPointToLayerPoint([0, 0]));
      this._scheduleDraw();
    },

    _scheduleDraw() {
      if (this._frame) return;
      this._frame = requestAnimationFrame(() => {
        this._frame = null;
        this._draw();
      });
    },

    _draw() {
      const map = this._map;
      if (!map) return;

      const ctx = this._ctx;
      const dpr = window.devicePixelRatio || 1;
      const size = map.getSize();

      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, size.x, size.y);

      const bounds = map.getBounds().pad(0.15);
      const segments = engine.index.inBounds(
        bounds.getSouth(), bounds.getWest(), bounds.getNorth(), bounds.getEast()
      );

      // Project once per segment, reused by the fog pass and the neon pass.
      const drawables = [];
      for (const segment of segments) {
        const entry = engine.coverage.get(segment.id);
        const runs = [];
        if (entry) {
          for (const [lower, upper] of entry.intervals) {
            const points = subPolyline(segment, lower, upper);
            if (points.length > 1) runs.push(points.map((p) => map.latLngToContainerPoint([p.lat, p.lon])));
          }
        }
        drawables.push({
          segment,
          runs,
          complete: entry ? coveredFraction(entry.intervals) >= COMPLETION_THRESHOLD : false,
          hot: engine.sessionSegmentIDs.has(segment.id),
          path: entry ? null : segment.points.map((p) => map.latLngToContainerPoint([p.lat, p.lon])),
        });
      }

      const zoomScale = Math.max(0.6, Math.min(2.4, (map.getZoom() - 12) * 0.28 + 1));

      if (settings.fog) this._drawFog(ctx, size, drawables, zoomScale);
      this._drawStreets(ctx, drawables, segments.length, zoomScale);
    },

    /** Darkens everywhere you haven't been and cuts a soft-edged corridor
     *  along everywhere you have. */
    _drawFog(ctx, size, drawables, zoomScale) {
      ctx.save();
      ctx.fillStyle = "rgba(10, 14, 20, 0.72)";
      ctx.fillRect(0, 0, size.x, size.y);

      // Stacking a wide faint clear under a narrow opaque one gives the
      // corridor a soft edge instead of a hard slot.
      ctx.globalCompositeOperation = "destination-out";
      ctx.lineCap = "round";
      ctx.lineJoin = "round";

      for (const [width, alpha] of [[54, 0.3], [32, 0.45], [18, 1]]) {
        ctx.strokeStyle = `rgba(0, 0, 0, ${alpha})`;
        ctx.lineWidth = width * zoomScale;
        for (const drawable of drawables) {
          for (const run of drawable.runs) tracePath(ctx, run);
        }
      }
      ctx.restore();
    },

    _drawStreets(ctx, drawables, totalInView, zoomScale) {
      const base = Math.max(1.6, 3.2 * zoomScale);
      ctx.lineCap = "round";
      ctx.lineJoin = "round";

      if (settings.showUncollected && totalInView <= UNCOLLECTED_DRAW_LIMIT) {
        // Barely there: a suggestion of a grid waiting to be lit, not a second
        // map competing with the first.
        ctx.strokeStyle = `rgba(${INK.uncollected}, 0.3)`;
        ctx.lineWidth = base * 0.55;
        for (const drawable of drawables) {
          if (drawable.path) tracePath(ctx, drawable.path);
        }
      }

      // Three passes per lit street — wide haze, mid bloom, bright core —
      // which fakes a neon glow far more cheaply than a real blur.
      const passes = [[3.6, 0.13], [1.9, 0.3], [1, 1]];

      for (const drawable of drawables) {
        if (!drawable.runs.length) continue;
        const colour = drawable.hot ? INK.hot : drawable.complete ? INK.collected : INK.partial;

        for (const [widthScale, alpha] of passes) {
          ctx.strokeStyle = `rgba(${colour}, ${alpha})`;
          ctx.lineWidth = base * widthScale;
          for (const run of drawable.runs) tracePath(ctx, run);
        }

        // Finished streets get a white-hot centre line, so a fully collected
        // street is unmistakable from a nearly-collected one.
        if (drawable.complete) {
          ctx.strokeStyle = "rgba(255, 255, 255, 0.55)";
          ctx.lineWidth = Math.max(0.5, base * 0.3);
          for (const run of drawable.runs) tracePath(ctx, run);
        }
      }
    },
  });
}

function tracePath(ctx, points) {
  if (points.length < 2) return;
  ctx.beginPath();
  ctx.moveTo(points[0].x, points[0].y);
  for (let i = 1; i < points.length; i++) ctx.lineTo(points[i].x, points[i].y);
  ctx.stroke();
}

/** Builds the map, the coverage layer and the player marker. */
export function buildMap(element, engine, settings) {
  const map = L.map(element, {
    zoomControl: false,
    attributionControl: true,
    preferCanvas: true,
    tap: false,
  }).setView([51.5074, -0.1278], 15);

  // CARTO's dark basemap, because the collection reads as light on darkness.
  L.tileLayer("https://{s}.basemaps.cartocdn.com/dark_nolabels/{z}/{x}/{y}{r}.png", {
    attribution:
      '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors &copy; <a href="https://carto.com/attributions">CARTO</a>',
    subdomains: "abcd",
    maxZoom: 20,
  }).addTo(map);

  // Labels go on top of the coverage canvas so street names stay readable
  // through the fog.
  const labels = L.tileLayer("https://{s}.basemaps.cartocdn.com/dark_only_labels/{z}/{x}/{y}{r}.png", {
    subdomains: "abcd",
    maxZoom: 20,
    pane: "shadowPane",
  }).addTo(map);

  const CoverageLayer = createCoverageLayer(engine, settings);
  const coverage = new CoverageLayer().addTo(map);

  const playerIcon = L.divIcon({
    className: "player-marker",
    html: '<div class="player-halo"></div><div class="player-core"></div>',
    iconSize: [26, 26],
    iconAnchor: [13, 13],
  });
  const player = L.marker([0, 0], { icon: playerIcon, interactive: false, zIndexOffset: 1000 });

  return { map, coverage, player, labels };
}
