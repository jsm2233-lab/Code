// Snaps raw GPS fixes onto street segments. Port of MapMatcher.swift.
//
// The heart of the app. Naive "nearest polyline" produces a mess on dual
// carriageways, at junctions and beside parallel service roads, so matching is
// scored on three things: perpendicular distance, agreement between the fix's
// course and the road's bearing, and stickiness toward the segment matched
// last. Stickiness is what stops the match flickering between a road and the
// cycle path running alongside it.

import { bearing, distance, angleDelta, undirectedAngleDelta, project } from "./geo.js";

export const MATCHER_CONFIG = {
  maxHorizontalAccuracy: 40,   // fixes worse than this are thrown away
  baseSearchRadius: 25,
  maxAcceptableScore: 60,      // beyond this, the fix goes unmatched
  stickinessBonus: 18,         // metres of score forgiven for staying put
  headingPenaltyPerDegree: 0.7,
  minimumSpeedForHeading: 1.5, // below this, reported course is noise
  maxBridgeInterval: 25,       // seconds
  maxBridgeDistance: 250,      // metres
};

export class MapMatcher {
  constructor(index, config = MATCHER_CONFIG) {
    this.index = index;
    this.config = config;
    this.previous = null;
  }

  reset() {
    this.previous = null;
  }

  /**
   * Feeds one fix in. Returns { match, traversal, rejected }, where traversal
   * is the stretch of road this fix proves was covered.
   */
  process(fix) {
    const config = this.config;
    if (!(fix.accuracy > 0) || fix.accuracy > config.maxHorizontalAccuracy) {
      return { match: null, traversal: null, rejected: "accuracy" };
    }

    const point = { lat: fix.lat, lon: fix.lon };
    const radius = Math.max(config.baseSearchRadius, fix.accuracy * 1.5);
    const candidates = this.index.candidates(point, radius);
    if (!candidates.length) {
      this.previous = null;
      return { match: null, traversal: null, rejected: "no-candidates" };
    }

    const heading =
      fix.heading != null && fix.heading >= 0 && fix.speed >= config.minimumSpeedForHeading
        ? fix.heading
        : null;

    let best = null;
    for (const segment of candidates) {
      const scored = this._score(segment, point, heading, fix.time);
      if (scored && (!best || scored.score < best.score)) best = scored;
    }

    if (!best || best.score > config.maxAcceptableScore) {
      this.previous = null;
      return { match: null, traversal: null, rejected: "no-confident-match" };
    }

    const traversal = this._traversal(best, this.previous, fix.accuracy);
    this.previous = best;
    return { match: best, traversal, rejected: null };
  }

  _score(segment, point, heading, time) {
    const points = segment.points;
    if (points.length < 2) return null;

    let bestDistance = Infinity;
    let bestT = 0;
    let bestLocalBearing = 0;
    let travelled = 0;

    for (let i = 1; i < points.length; i++) {
      const a = points[i - 1];
      const b = points[i];
      const step = distance(a, b);
      const projection = project(point, a, b);
      if (projection.distance < bestDistance) {
        bestDistance = projection.distance;
        bestT = segment.length > 0 ? (travelled + projection.t * step) / segment.length : 0;
        bestLocalBearing = bearing(a, b);
      }
      travelled += step;
    }

    let total = bestDistance;

    if (heading != null) {
      // One-way streets can be penalised directionally; two-way streets are
      // equally valid in either direction.
      const delta = segment.oneway
        ? angleDelta(heading, bestLocalBearing)
        : undirectedAngleDelta(heading, bestLocalBearing);
      total += delta * this.config.headingPenaltyPerDegree;
    }

    if (this.previous) {
      if (this.previous.segment.id === segment.id) {
        total -= this.config.stickinessBonus;
      } else if (sharesEndpoint(this.previous.segment, segment)) {
        // A segment we could plausibly have turned onto gets a smaller bonus,
        // so junctions hand off cleanly instead of snapping back.
        total -= this.config.stickinessBonus * 0.5;
      }
    }

    return {
      segment,
      t: Math.max(0, Math.min(1, bestT)),
      perpendicular: bestDistance,
      score: total,
      time,
    };
  }

  /**
   * Two fixes on the same segment mean everything between them was travelled.
   * A single fix only proves we were within GPS error of one point, so it marks
   * a small window instead.
   */
  _traversal(match, previous, accuracy) {
    const segment = match.segment;
    if (segment.length <= 1) return null;

    if (previous && previous.segment.id === segment.id) {
      const gap = (match.time - previous.time) / 1000;
      const jump = Math.abs(match.t - previous.t) * segment.length;
      if (gap <= this.config.maxBridgeInterval && jump <= this.config.maxBridgeDistance) {
        return {
          segment,
          lower: Math.min(previous.t, match.t),
          upper: Math.max(previous.t, match.t),
        };
      }
    }

    const window = Math.max(6, accuracy * 0.5) / segment.length;
    return { segment, lower: match.t - window, upper: match.t + window };
  }
}

function sharesEndpoint(a, b) {
  const tolerance = 12;
  const aStart = a.points[0];
  const aEnd = a.points[a.points.length - 1];
  const bStart = b.points[0];
  const bEnd = b.points[b.points.length - 1];
  return (
    distance(aStart, bStart) < tolerance ||
    distance(aStart, bEnd) < tolerance ||
    distance(aEnd, bStart) < tolerance ||
    distance(aEnd, bEnd) < tolerance
  );
}
