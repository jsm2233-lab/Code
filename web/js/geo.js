// Planar geometry helpers. Direct port of Core/GeoMath.swift.
//
// Everything works in a local metre frame anchored on a reference latitude.
// Over the few-hundred-metre distances the matcher cares about, the error from
// ignoring curvature is far below GPS noise.

export const EARTH_RADIUS = 6371008.8;
export const METRES_PER_DEG_LAT = (Math.PI * EARTH_RADIUS) / 180;

export function metresPerDegLon(latitude) {
  return METRES_PER_DEG_LAT * Math.cos((latitude * Math.PI) / 180);
}

export function distance(a, b) {
  const lat1 = (a.lat * Math.PI) / 180;
  const lat2 = (b.lat * Math.PI) / 180;
  const dLat = lat2 - lat1;
  const dLon = ((b.lon - a.lon) * Math.PI) / 180;
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) ** 2;
  return 2 * EARTH_RADIUS * Math.asin(Math.min(1, Math.sqrt(h)));
}

export function bearing(a, b) {
  const lat1 = (a.lat * Math.PI) / 180;
  const lat2 = (b.lat * Math.PI) / 180;
  const dLon = ((b.lon - a.lon) * Math.PI) / 180;
  const y = Math.sin(dLon) * Math.cos(lat2);
  const x =
    Math.cos(lat1) * Math.sin(lat2) -
    Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLon);
  return ((Math.atan2(y, x) * 180) / Math.PI) % 360;
}

export function angleDelta(a, b) {
  let d = Math.abs(a - b) % 360;
  if (d > 180) d = 360 - d;
  return d;
}

/** Treats a heading and its reverse as equal: a two-way street is the same
 *  street in either direction. */
export function undirectedAngleDelta(a, b) {
  const d = angleDelta(a, b);
  return Math.min(d, 180 - d);
}

/** Projects a point onto segment a-b. Returns metres off the line, and the
 *  position along it as a fraction clamped to 0..1. */
export function project(point, a, b) {
  const mLat = METRES_PER_DEG_LAT;
  const mLon = metresPerDegLon(a.lat);

  const bx = (b.lon - a.lon) * mLon;
  const by = (b.lat - a.lat) * mLat;
  const px = (point.lon - a.lon) * mLon;
  const py = (point.lat - a.lat) * mLat;

  const lengthSquared = bx * bx + by * by;
  if (lengthSquared < 1e-9) {
    return { distance: Math.hypot(px, py), t: 0 };
  }

  const t = Math.max(0, Math.min(1, (px * bx + py * by) / lengthSquared));
  return { distance: Math.hypot(px - t * bx, py - t * by), t };
}

export function interpolate(a, b, t) {
  return { lat: a.lat + (b.lat - a.lat) * t, lon: a.lon + (b.lon - a.lon) * t };
}

export function polylineLength(points) {
  let total = 0;
  for (let i = 1; i < points.length; i++) total += distance(points[i - 1], points[i]);
  return total;
}
