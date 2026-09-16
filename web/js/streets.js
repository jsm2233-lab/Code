// Street model, tiles, and the Overpass import. Ports StreetSegment.swift,
// TileKey.swift and OverpassClient.swift.

import { distance, polylineLength, interpolate } from "./geo.js";

// Street data is fetched, cached and expired a tile at a time. A fixed 0.02
// deg grid: small enough that one Overpass query returns quickly, big enough
// that a normal commute doesn't thrash the network.
export const TILE_SIZE = 0.02;

export function tileKey(lat, lon) {
  return `${Math.floor(lon / TILE_SIZE)}_${Math.floor(lat / TILE_SIZE)}`;
}

export function tileBounds(key) {
  const [x, y] = key.split("_").map(Number);
  return {
    west: x * TILE_SIZE,
    south: y * TILE_SIZE,
    east: (x + 1) * TILE_SIZE,
    north: (y + 1) * TILE_SIZE,
  };
}

/** The 3x3 block around a tile. Prefetching the ring means the user rarely
 *  crosses into an unloaded tile at speed. */
export function tileNeighbourhood(key) {
  const [x, y] = key.split("_").map(Number);
  const keys = [];
  for (let dx = -1; dx <= 1; dx++) for (let dy = -1; dy <= 1; dy++) keys.push(`${x + dx}_${y + dy}`);
  return keys;
}

export function tilesCovering(bounds, limit = 25) {
  const x0 = Math.floor(bounds.west / TILE_SIZE);
  const x1 = Math.floor(bounds.east / TILE_SIZE);
  const y0 = Math.floor(bounds.south / TILE_SIZE);
  const y1 = Math.floor(bounds.north / TILE_SIZE);
  if ((x1 - x0 + 1) * (y1 - y0 + 1) > limit) return [];
  const keys = [];
  for (let x = x0; x <= x1; x++) for (let y = y0; y <= y1; y++) keys.push(`${x}_${y}`);
  return keys;
}

// OSM highway classes, collapsed to the handful that change scoring or drawing.
const CLASS_MAP = {
  motorway: "motorway", motorway_link: "motorway",
  trunk: "trunk", trunk_link: "trunk",
  primary: "primary", primary_link: "primary",
  secondary: "secondary", secondary_link: "secondary",
  tertiary: "tertiary", tertiary_link: "tertiary",
  residential: "residential", unclassified: "residential",
  living_street: "living",
  service: "service",
  pedestrian: "pedestrian", footway: "pedestrian", steps: "pedestrian",
  track: "track",
  path: "path", cycleway: "path", bridleway: "path",
};

export const CLASS_INFO = {
  // Backstreets are worth more than motorway: the point is the fiddly bits.
  motorway: { label: "Motorway", multiplier: 0.5, counts: true },
  trunk: { label: "Trunk road", multiplier: 0.5, counts: true },
  primary: { label: "Primary road", multiplier: 0.8, counts: true },
  secondary: { label: "Secondary road", multiplier: 1.0, counts: true },
  tertiary: { label: "Tertiary road", multiplier: 1.0, counts: true },
  residential: { label: "Residential street", multiplier: 1.4, counts: true },
  living: { label: "Living street", multiplier: 1.4, counts: true },
  // Collectible, but they don't dilute the city-completion percentage.
  service: { label: "Service road", multiplier: 0.7, counts: false },
  pedestrian: { label: "Pedestrian way", multiplier: 1.2, counts: false },
  path: { label: "Path", multiplier: 1.2, counts: false },
  track: { label: "Track", multiplier: 1.0, counts: false },
};

const UNNAMED = {
  motorway: "Unnamed motorway", trunk: "Unnamed trunk road",
  primary: "Unnamed road", secondary: "Unnamed road", tertiary: "Unnamed road",
  residential: "Unnamed street", living: "Unnamed street",
  service: "Service road", pedestrian: "Footpath", track: "Track", path: "Path",
};

export function displayName(segment) {
  return segment.name || UNNAMED[segment.klass] || "Unnamed street";
}

function boundingBox(points) {
  let minLat = Infinity, minLon = Infinity, maxLat = -Infinity, maxLon = -Infinity;
  for (const p of points) {
    if (p.lat < minLat) minLat = p.lat;
    if (p.lat > maxLat) maxLat = p.lat;
    if (p.lon < minLon) minLon = p.lon;
    if (p.lon > maxLon) maxLon = p.lon;
  }
  return { minLat, minLon, maxLat, maxLon };
}

export function coordinateAtFraction(segment, t) {
  const points = segment.points;
  if (points.length < 2) return points[0];
  const target = Math.max(0, Math.min(1, t)) * segment.length;
  let travelled = 0;
  for (let i = 1; i < points.length; i++) {
    const step = distance(points[i - 1], points[i]);
    if (travelled + step >= target) {
      const local = step > 0 ? (target - travelled) / step : 0;
      return interpolate(points[i - 1], points[i], local);
    }
    travelled += step;
  }
  return points[points.length - 1];
}

/** Sub-polyline covering lower..upper in segment fractions, for drawing
 *  partial progress. */
export function subPolyline(segment, lower, upper) {
  const points = segment.points;
  if (points.length < 2 || upper <= lower) return [];
  const startDistance = Math.max(0, Math.min(1, lower)) * segment.length;
  const endDistance = Math.max(0, Math.min(1, upper)) * segment.length;

  const result = [coordinateAtFraction(segment, lower)];
  let travelled = 0;
  for (let i = 1; i < points.length; i++) {
    const vertexDistance = travelled + distance(points[i - 1], points[i]);
    if (vertexDistance > startDistance && vertexDistance < endDistance) result.push(points[i]);
    travelled = vertexDistance;
    if (travelled >= endDistance) break;
  }
  result.push(coordinateAtFraction(segment, upper));
  return result;
}

/**
 * Splits each way at nodes shared with another way, so a segment is always
 * intersection-to-intersection. Without this, "collecting a street" would mean
 * wildly different amounts of travel depending on how OSM chopped the way up.
 */
export function segmentsFromElements(elements, tile) {
  const nodeUse = new Map();
  for (const element of elements) {
    if (!element.nodes) continue;
    for (const node of element.nodes) nodeUse.set(node, (nodeUse.get(node) || 0) + 1);
  }

  const result = [];

  for (const element of elements) {
    const highway = element.tags && element.tags.highway;
    const klass = CLASS_MAP[highway];
    const geometry = element.geometry;
    if (!klass || !geometry || geometry.length < 2) continue;

    const nodes = element.nodes || [];
    const name = (element.tags && element.tags.name) || null;
    const oneway = ["yes", "1", "-1"].includes(element.tags && element.tags.oneway);

    let current = [{ lat: geometry[0].lat, lon: geometry[0].lon }];
    let piece = 0;

    for (let i = 1; i < geometry.length; i++) {
      current.push({ lat: geometry[i].lat, lon: geometry[i].lon });

      const isLast = i === geometry.length - 1;
      const isJunction = i < nodes.length && (nodeUse.get(nodes[i]) || 0) > 1;

      if (isLast || isJunction) {
        const length = polylineLength(current);
        // Sub-5 m stubs are junction artefacts, not streets.
        if (length >= 5) {
          result.push({
            id: `${element.id}-${piece}`,
            name,
            klass,
            points: current,
            length,
            oneway,
            tile,
            bbox: boundingBox(current),
          });
        }
        piece += 1;
        current = [current[current.length - 1]];
      }
    }
  }

  return result;
}

// Public Overpass instances, rotated on failure. These are donated servers and
// the usage policy asks for restraint, hence the throttle below.
const ENDPOINTS = [
  "https://overpass-api.de/api/interpreter",
  "https://overpass.kumi.systems/api/interpreter",
];

let endpointIndex = 0;
let nextAllowed = 0;

export async function fetchTile(key) {
  const wait = nextAllowed - Date.now();
  if (wait > 0) await new Promise((resolve) => setTimeout(resolve, wait));
  nextAllowed = Date.now() + 1200;

  const b = tileBounds(key);
  const query = `[out:json][timeout:45];
way["highway"]["highway"!~"^(proposed|construction|abandoned|raceway|bus_guideway|escape)$"]["area"!="yes"](${b.south},${b.west},${b.north},${b.east});
out geom;`;

  const response = await fetch(ENDPOINTS[endpointIndex], {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: "data=" + encodeURIComponent(query),
  });

  if (!response.ok) {
    endpointIndex = (endpointIndex + 1) % ENDPOINTS.length;
    nextAllowed = Date.now() + 5000;
    throw new Error(`Overpass returned ${response.status}`);
  }

  const payload = await response.json();
  return segmentsFromElements(payload.elements || [], key);
}
