// Ties the pieces together: positions in, matched streets and score out.
// Ports CollectionEngine.swift, CoverageStore.swift and StreetDataStore.swift.

import { distance } from "./geo.js";
import { SpatialIndex } from "./spatial.js";
import { MapMatcher } from "./matcher.js";
import { coveredFraction, insert } from "./intervals.js";
import { db, prefs } from "./store.js";
import { Game } from "./game.js";
import {
  CLASS_INFO, displayName, fetchTile, tileKey, tileNeighbourhood, tilesCovering,
} from "./streets.js";

// A segment counts as collected once you've covered most of it. Deliberately
// below 1.0: GPS drops out under bridges and at junction approaches, and
// demanding 100% would make long streets feel broken.
export const COMPLETION_THRESHOLD = 0.7;

// Street data older than a fortnight is refetched. Streets change slowly.
const TILE_MAX_AGE = 14 * 24 * 3600 * 1000;

// Track points are only appended after this much movement, so a long drive
// doesn't serialise thousands of coordinates.
const TRACK_POINT_SPACING = 20;

export class Engine extends EventTarget {
  constructor() {
    super();
    this.index = new SpatialIndex();
    this.matcher = new MapMatcher(this.index);
    this.game = new Game();

    this.coverage = new Map();      // segment id -> { intervals, first, last, visits }
    this.trips = [];
    this.loadedTiles = new Set();
    this.loadingTiles = new Set();
    this.failedTiles = new Map();
    this.tileFetchedAt = prefs.get("tileFetchedAt", {});

    this.activeTrip = null;
    this.sessionSegmentIDs = new Set();
    this.currentSegment = null;
    this.matchQuality = "unknown";
    this.lastFix = null;
    this.lastError = null;

    this._watchId = null;
    this._wakeLock = null;
    this._saveTimer = null;
    this._lastTileCheck = null;
    this._lastTrackFix = null;
    this._speeds = [];
  }

  async load() {
    const saved = await db.get("coverage", "all");
    if (saved) {
      for (const record of saved) {
        this.coverage.set(record[0], {
          intervals: record[1],
          first: record[2],
          last: record[3],
          visits: record[4] || 1,
        });
      }
    }
    this.trips = (await db.all("trips")) || [];
    this.trips.sort((a, b) => b.startedAt - a.startedAt);
    this._emit("loaded");
  }

  // MARK: - Geolocation

  get isTracking() {
    return this._watchId !== null;
  }

  /**
   * Starts a trip. iOS only delivers positions while the page is visible, so
   * the wake lock is not a nicety here: without it, a locked screen ends
   * collection silently.
   */
  async startTrip() {
    if (this.activeTrip) return;
    if (!navigator.geolocation) {
      this.lastError = "This browser has no geolocation.";
      this._emit("change");
      return;
    }

    this.matcher.reset();
    this._lastTrackFix = null;
    this._speeds = [];
    this.sessionSegmentIDs.clear();
    this.activeTrip = {
      id: crypto.randomUUID(),
      startedAt: Date.now(),
      endedAt: null,
      distance: 0,
      newStreetMetres: 0,
      newSegmentIDs: [],
      completedSegmentIDs: [],
      xp: 0,
      mode: "unknown",
      track: [],
    };

    this._watchId = navigator.geolocation.watchPosition(
      (position) => this._handlePosition(position),
      (error) => {
        this.lastError = geolocationMessage(error);
        this._emit("change");
      },
      { enableHighAccuracy: true, maximumAge: 0, timeout: 20000 }
    );

    await this._acquireWakeLock();
    this._emit("change");
  }

  async endTrip() {
    if (!this.activeTrip) return;

    if (this._watchId !== null) {
      navigator.geolocation.clearWatch(this._watchId);
      this._watchId = null;
    }
    await this._releaseWakeLock();

    const trip = this.activeTrip;
    trip.endedAt = Date.now();
    trip.mode = this._inferredMode();
    this.activeTrip = null;
    this.currentSegment = null;

    // A trip that collected nothing is noise in the history.
    if (trip.distance > 50) {
      this.trips.unshift(trip);
      await db.put("trips", undefined, trip);
    }

    await this.flush();
    this.game.evaluate(this.stats());
    this._emit("change");
  }

  toggleTrip() {
    return this.activeTrip ? this.endTrip() : this.startTrip();
  }

  async _acquireWakeLock() {
    if (!("wakeLock" in navigator)) return;
    try {
      this._wakeLock = await navigator.wakeLock.request("screen");
      // Safari drops the lock whenever the page is hidden; retake it on return.
      this._wakeLock.addEventListener("release", () => {
        this._wakeLock = null;
      });
    } catch {
      this._wakeLock = null;
    }
  }

  async _releaseWakeLock() {
    try {
      await this._wakeLock?.release();
    } catch {
      // Already gone.
    }
    this._wakeLock = null;
  }

  /** Called when the tab becomes visible again, since iOS releases the lock and
   *  suspends the position watch on backgrounding. */
  async handleVisible() {
    if (this.activeTrip && !this._wakeLock) await this._acquireWakeLock();
    this.game.refreshStreak();
  }

  // MARK: - The hot path

  _handlePosition(position) {
    const c = position.coords;
    const fix = {
      lat: c.latitude,
      lon: c.longitude,
      accuracy: c.accuracy,
      heading: c.heading == null || Number.isNaN(c.heading) ? -1 : c.heading,
      speed: c.speed == null || Number.isNaN(c.speed) ? -1 : c.speed,
      time: position.timestamp,
    };
    this.lastFix = fix;
    this.lastError = null;

    // Keep the street graph loaded ahead of the user. Only re-check after a few
    // hundred metres; this runs on every fix.
    const point = { lat: fix.lat, lon: fix.lon };
    if (!this._lastTileCheck || distance(this._lastTileCheck, point) > 300) {
      this._lastTileCheck = point;
      const key = tileKey(fix.lat, fix.lon);
      this.game.setHomeTile(key);
      this.loadTiles(tileNeighbourhood(key));
    }

    if (!this.activeTrip) {
      this._emit("position");
      return;
    }

    this._accumulateDistance(fix);
    this._appendTrackPoint(fix);
    if (fix.speed >= 0) this._speeds.push(fix.speed);

    const result = this.matcher.process(fix);
    this.matchQuality =
      result.rejected === "accuracy" ? "weak" : result.rejected ? "off-road" : "good";
    if (result.rejected) this.currentSegment = null;

    if (result.traversal) {
      this.currentSegment = result.traversal.segment;
      const delta = this._record(result.traversal, fix.time);
      if (delta) {
        this.sessionSegmentIDs.add(delta.segment.id);
        const mode = inferMode(fix.speed);
        const xp = this.game.award(delta, mode, fix.time);
        this.activeTrip.newStreetMetres += delta.newMetres;
        this.activeTrip.xp += xp;
        if (delta.firstTouch) this.activeTrip.newSegmentIDs.push(delta.segment.id);
        if (delta.completedNow) this.activeTrip.completedSegmentIDs.push(delta.segment.id);
      }
    }

    this._emit("position");
  }

  _record(traversal, time) {
    const segment = traversal.segment;
    const existing = this.coverage.get(segment.id);
    const firstTouch = !existing;
    const entry = existing || { intervals: [], first: time, last: time, visits: 1 };

    const fractionBefore = coveredFraction(entry.intervals);
    const wasComplete = fractionBefore >= COMPLETION_THRESHOLD;

    entry.intervals = insert(entry.intervals, traversal.lower, traversal.upper);
    entry.last = time;

    const fractionAfter = coveredFraction(entry.intervals);
    const gained = fractionAfter - fractionBefore;
    if (gained <= 0 && !firstTouch) return null;

    this.coverage.set(segment.id, entry);
    this._scheduleSave();

    return {
      segment,
      newMetres: gained * segment.length,
      completedNow: !wasComplete && fractionAfter >= COMPLETION_THRESHOLD,
      firstTouch,
      fractionAfter,
    };
  }

  _accumulateDistance(fix) {
    const previous = this._lastTrackFix;
    if (!previous) {
      this._lastTrackFix = fix;
      return;
    }
    const step = distance({ lat: previous.lat, lon: previous.lon }, { lat: fix.lat, lon: fix.lon });
    const interval = Math.max(0.5, (fix.time - previous.time) / 1000);
    // Reject teleports: a fix implying an impossible speed is a bad fix, not a
    // fast car.
    if (step >= 500 || step / interval >= 70) return;
    this.activeTrip.distance += step;
    this.game.addDistance(step);
  }

  _appendTrackPoint(fix) {
    const track = this.activeTrip.track;
    const point = { lat: fix.lat, lon: fix.lon };
    if (track.length) {
      const last = track[track.length - 1];
      if (distance(last, point) < TRACK_POINT_SPACING) return;
    }
    track.push(point);
    this._lastTrackFix = fix;
  }

  _inferredMode() {
    if (!this._speeds.length) return "unknown";
    const sorted = [...this._speeds].sort((a, b) => a - b);
    // Median, not mean: traffic lights drag a mean toward walking.
    return inferMode(sorted[Math.floor(sorted.length / 2)]);
  }

  // MARK: - Street data

  async loadTiles(keys) {
    for (const key of keys) {
      if (this.loadedTiles.has(key) || this.loadingTiles.has(key)) continue;
      // Back off on tiles that keep failing, so a genuinely empty or
      // unreachable tile doesn't retry on every position update.
      if ((this.failedTiles.get(key) || 0) >= 5) continue;
      this._loadTile(key);
    }
  }

  loadTilesForBounds(bounds) {
    return this.loadTiles(tilesCovering(bounds));
  }

  async _loadTile(key) {
    this.loadingTiles.add(key);
    this._emit("tiles");

    const cached = await db.get("tiles", key);
    const fetchedAt = this.tileFetchedAt[key] || 0;
    const fresh = Date.now() - fetchedAt < TILE_MAX_AGE;

    if (cached && fresh) {
      this.index.insertAll(cached);
      this.loadedTiles.add(key);
      this.loadingTiles.delete(key);
      this._emit("tiles");
      return;
    }

    try {
      const segments = await fetchTile(key);
      await db.put("tiles", key, segments);
      this.tileFetchedAt[key] = Date.now();
      prefs.set("tileFetchedAt", this.tileFetchedAt);
      this.index.removeTile(key);
      this.index.insertAll(segments);
      this.loadedTiles.add(key);
      this.failedTiles.delete(key);
      this.lastError = null;
    } catch (error) {
      this.failedTiles.set(key, (this.failedTiles.get(key) || 0) + 1);
      // Stale cache beats no map: if the network is gone, use whatever we
      // downloaded last time rather than showing an empty city.
      if (cached) {
        this.index.insertAll(cached);
        this.loadedTiles.add(key);
      } else {
        this.lastError = `Street data: ${error.message}`;
      }
    } finally {
      this.loadingTiles.delete(key);
      this._emit("tiles");
    }
  }

  async refreshTile(key) {
    delete this.tileFetchedAt[key];
    prefs.set("tileFetchedAt", this.tileFetchedAt);
    this.loadedTiles.delete(key);
    this.failedTiles.delete(key);
    this.index.removeTile(key);
    await db.delete("tiles", key);
    return this.loadTiles([key]);
  }

  async clearStreetCache() {
    this.index.clear();
    this.loadedTiles.clear();
    this.tileFetchedAt = {};
    prefs.set("tileFetchedAt", {});
    await db.clear("tiles");
    this._emit("tiles");
  }

  // MARK: - Reads

  fractionFor(id) {
    const entry = this.coverage.get(id);
    return entry ? coveredFraction(entry.intervals) : 0;
  }

  isComplete(id) {
    return this.fractionFor(id) >= COMPLETION_THRESHOLD;
  }

  get completedCount() {
    let count = 0;
    for (const entry of this.coverage.values()) {
      if (coveredFraction(entry.intervals) >= COMPLETION_THRESHOLD) count++;
    }
    return count;
  }

  get touchedCount() {
    return this.coverage.size;
  }

  /** Completion of one tile, counting only classes that count toward the
   *  headline percentage. */
  tileCompletion(key) {
    const segments = this.index.tileSegments(key).filter((s) => CLASS_INFO[s.klass].counts);
    let completed = 0;
    let total = 0;
    let covered = 0;
    for (const segment of segments) {
      total += segment.length;
      const fraction = this.fractionFor(segment.id);
      covered += fraction * segment.length;
      if (fraction >= COMPLETION_THRESHOLD) completed++;
    }
    return {
      key,
      segments: segments.length,
      completed,
      metresTotal: total,
      metresCovered: covered,
      fraction: total > 0 ? covered / total : 0,
    };
  }

  bestTilePercent() {
    let best = 0;
    for (const key of this.loadedTiles) {
      const completion = this.tileCompletion(key);
      if (completion.segments > 0) best = Math.max(best, completion.fraction * 100);
    }
    return best;
  }

  /** The collection book: one row per real-world street name, not per OSM
   *  fragment. */
  collectedStreets() {
    const grouped = new Map();
    for (const [id, entry] of this.coverage) {
      const segment = this.index.get(id);
      if (!segment) continue;
      const key = segment.name || `unnamed-${id}`;
      let street = grouped.get(key);
      if (!street) {
        street = {
          name: displayName(segment),
          klass: segment.klass,
          segments: 0,
          completed: 0,
          metresTotal: 0,
          metresCovered: 0,
          first: entry.first,
          last: entry.last,
        };
        grouped.set(key, street);
      }
      const fraction = coveredFraction(entry.intervals);
      street.segments += 1;
      if (fraction >= COMPLETION_THRESHOLD) street.completed += 1;
      street.metresTotal += segment.length;
      street.metresCovered += fraction * segment.length;
      street.first = Math.min(street.first, entry.first);
      street.last = Math.max(street.last, entry.last);
    }
    return [...grouped.values()]
      .map((street) => ({
        ...street,
        fraction: street.metresTotal > 0 ? street.metresCovered / street.metresTotal : 0,
        fullyCollected: street.completed === street.segments,
      }))
      .sort((a, b) => b.last - a.last);
  }

  /** Nearby streets you haven't finished, closest first. The app's "what next"
   *  list. */
  suggestions(point, limit = 25) {
    return this.index
      .candidates(point, 1200)
      .filter((segment) => CLASS_INFO[segment.klass].counts)
      .map((segment) => ({
        segment,
        fraction: this.fractionFor(segment.id),
        distance: distance(point, segment.points[Math.floor(segment.points.length / 2)]),
      }))
      .filter((suggestion) => suggestion.fraction < COMPLETION_THRESHOLD)
      .sort((a, b) => a.distance - b.distance)
      .slice(0, limit);
  }

  stats() {
    const names = new Set();
    let nightCount = 0;
    for (const [id, entry] of this.coverage) {
      if (coveredFraction(entry.intervals) < COMPLETION_THRESHOLD) continue;
      const segment = this.index.get(id);
      if (segment && segment.name) names.add(segment.name);
      if (new Date(entry.first).getHours() < 5) nightCount++;
    }
    return {
      completedCount: this.completedCount,
      distinctNamedCount: names.size,
      nightCount,
      bestTilePercent: this.bestTilePercent(),
      bestTripNewMetres: this.trips.reduce((best, t) => Math.max(best, t.newStreetMetres), 0),
      walkingNewMetres: this.trips
        .filter((t) => t.mode === "walking")
        .reduce((total, t) => total + t.newStreetMetres, 0),
    };
  }

  /** New-street metres per day for the last `days` days, oldest first. */
  dailyNewMetres(days = 30) {
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const buckets = new Map();
    for (const trip of this.trips) {
      const day = new Date(trip.startedAt);
      day.setHours(0, 0, 0, 0);
      const offset = Math.round((today - day) / 86400000);
      if (offset < 0 || offset >= days) continue;
      buckets.set(offset, (buckets.get(offset) || 0) + trip.newStreetMetres);
    }
    const result = [];
    for (let offset = days - 1; offset >= 0; offset--) {
      result.push({ offset, metres: buckets.get(offset) || 0 });
    }
    return result;
  }

  // MARK: - Lifecycle

  /** Coverage changes on every fix; writing each time would burn battery for
   *  nothing. Debounce, and flush on backgrounding. */
  _scheduleSave() {
    clearTimeout(this._saveTimer);
    this._saveTimer = setTimeout(() => this.flush(), 4000);
  }

  async flush() {
    clearTimeout(this._saveTimer);
    const records = [];
    for (const [id, entry] of this.coverage) {
      records.push([id, entry.intervals, entry.first, entry.last, entry.visits]);
    }
    await db.put("coverage", "all", records);
    this.game.save();
  }

  async resetEverything() {
    await this.endTrip();
    this.coverage.clear();
    this.trips = [];
    this.sessionSegmentIDs.clear();
    this.game.reset();
    await db.clear("coverage");
    await db.clear("trips");
    this._emit("change");
  }

  _emit(name) {
    this.dispatchEvent(new Event(name));
  }
}

export function inferMode(speed) {
  if (speed < 0) return "unknown";
  if (speed < 2.2) return "walking";
  if (speed < 7.0) return "cycling";
  return "driving";
}

function geolocationMessage(error) {
  switch (error.code) {
    case error.PERMISSION_DENIED:
      return "Location permission denied. Enable it in Settings → Safari → Location.";
    case error.POSITION_UNAVAILABLE:
      return "Position unavailable. Are you indoors?";
    case error.TIMEOUT:
      return "Timed out waiting for a fix.";
    default:
      return error.message || "Location failed.";
  }
}
