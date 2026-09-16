// Tests for the pure logic: geometry, interval merging, matching, way
// splitting, levelling. Ports StreetCollectorTests/.
//
// No framework, no dependencies: `npm test` or `node tests/run.mjs`.

import assert from "node:assert/strict";

import * as geo from "../js/geo.js";
import { coveredFraction, insert } from "../js/intervals.js";
import { SpatialIndex } from "../js/spatial.js";
import { MapMatcher } from "../js/matcher.js";
import { segmentsFromElements, subPolyline, coordinateAtFraction, tileKey, tileNeighbourhood } from "../js/streets.js";
import { levelForXP, xpRequired, MAX_LEVEL } from "../js/game.js";
import { inferMode } from "../js/engine.js";

let passed = 0;
const failures = [];

function test(name, fn) {
  try {
    fn();
    passed++;
  } catch (error) {
    failures.push({ name, error });
  }
}

const close = (actual, expected, tolerance, message) =>
  assert.ok(
    Math.abs(actual - expected) <= tolerance,
    `${message || ""} expected ${expected} ±${tolerance}, got ${actual}`
  );

// ---------- Geometry ----------

test("distance matches a known value", () => {
  const a = { lat: 51.5074, lon: -0.1278 };
  const b = { lat: 51.5174, lon: -0.1178 };
  // Haversine reference for these two points is ~1320 m.
  close(geo.distance(a, b), 1320, 15);
});

test("distance is symmetric and zero for identical points", () => {
  const a = { lat: 51.5, lon: -0.1 };
  const b = { lat: 51.6, lon: -0.2 };
  close(geo.distance(a, b), geo.distance(b, a), 1e-9);
  assert.equal(geo.distance(a, a), 0);
});

test("bearing due east is 90 degrees", () => {
  close(geo.bearing({ lat: 0, lon: 0 }, { lat: 0, lon: 1 }), 90, 0.5);
});

test("undirected angle delta treats reverse as same", () => {
  close(geo.undirectedAngleDelta(10, 190), 0, 1e-9);
  close(geo.undirectedAngleDelta(0, 90), 90, 1e-9);
});

test("projection onto midpoint", () => {
  const a = { lat: 51.5, lon: -0.1 };
  const b = { lat: 51.5, lon: -0.09 };
  const point = { lat: 51.5002, lon: (a.lon + b.lon) / 2 };
  const result = geo.project(point, a, b);
  close(result.t, 0.5, 0.02);
  close(result.distance, 22, 4);
});

test("projection clamps beyond the endpoints", () => {
  const result = geo.project({ lat: 0, lon: 0.01 }, { lat: 0, lon: 0 }, { lat: 0, lon: 0.001 });
  close(result.t, 1, 1e-6);
});

// ---------- Intervals ----------

test("intervals merge when they overlap", () => {
  let set = insert([], 0.1, 0.3);
  set = insert(set, 0.5, 0.7);
  assert.equal(set.length, 2);
  close(coveredFraction(set), 0.4, 1e-6);

  set = insert(set, 0.25, 0.55);
  assert.equal(set.length, 1, "a bridging interval should collapse the two");
  close(coveredFraction(set), 0.6, 1e-6);
});

test("intervals clamp to the unit range", () => {
  close(coveredFraction(insert([], -0.5, 1.5)), 1, 1e-6);
});

test("reversed bounds are normalised", () => {
  close(coveredFraction(insert([], 0.8, 0.2)), 0.6, 1e-6);
});

test("slivers are ignored", () => {
  assert.equal(insert([], 0.5, 0.50001).length, 0);
});

test("repeated identical inserts do not accumulate", () => {
  let set = [];
  for (let i = 0; i < 50; i++) set = insert(set, 0.2, 0.4);
  assert.equal(set.length, 1);
  close(coveredFraction(set), 0.2, 1e-6);
});

test("many disjoint inserts stay sorted", () => {
  let set = [];
  for (const start of [0.8, 0.1, 0.5, 0.3]) set = insert(set, start, start + 0.05);
  assert.deepEqual(
    set.map((i) => Number(i[0].toFixed(2))),
    [0.1, 0.3, 0.5, 0.8]
  );
});

// ---------- Street building ----------

function street(id, lat, name) {
  const points = [
    { lat, lon: -0.1 },
    { lat, lon: -0.097 },
  ];
  return {
    id, name, klass: "residential", points,
    length: geo.polylineLength(points),
    oneway: false,
    tile: tileKey(lat, -0.1),
    bbox: { minLat: lat, maxLat: lat, minLon: -0.1, maxLon: -0.097 },
  };
}

function makeIndex() {
  const index = new SpatialIndex();
  // An east-west street and a parallel one ~24 m north: the case that breaks
  // naive nearest-polyline matching.
  index.insert(street("main", 51.5, "Main Street"));
  index.insert(street("parallel", 51.50022, "Back Lane"));
  return index;
}

function fix(lat, lon, { heading = 90, speed = 8, accuracy = 8, time = 0 } = {}) {
  return { lat, lon, heading, speed, accuracy, time: 1700000000000 + time * 1000 };
}

// ---------- Spatial index ----------

test("candidate lookup finds nearby segments and nothing far away", () => {
  const index = makeIndex();
  assert.equal(index.candidates({ lat: 51.5, lon: -0.099 }, 30).length >= 1, true);
  assert.equal(index.candidates({ lat: 52, lon: 0 }, 30).length, 0);
});

test("removing a tile empties the index", () => {
  const index = new SpatialIndex();
  const segment = street("a", 51.5, "A Road");
  index.insert(segment);
  index.removeTile(segment.tile);
  assert.equal(index.size, 0);
  assert.equal(index.candidates(segment.points[0], 30).length, 0);
});

test("bounds query returns segments in view", () => {
  const index = makeIndex();
  assert.equal(index.inBounds(51.49, -0.11, 51.51, -0.09).length, 2);
  assert.equal(index.inBounds(51.6, -0.11, 51.61, -0.09).length, 0);
});

// ---------- Matcher ----------

test("matches the nearest street", () => {
  const matcher = new MapMatcher(makeIndex());
  const result = matcher.process(fix(51.50001, -0.099));
  assert.equal(result.match?.segment.id, "main");
  assert.equal(result.rejected, null);
});

test("rejects a poor-accuracy fix", () => {
  const matcher = new MapMatcher(makeIndex());
  const result = matcher.process(fix(51.50001, -0.099, { accuracy: 120 }));
  assert.equal(result.match, null);
  assert.equal(result.rejected, "accuracy");
});

test("stickiness keeps the match on the same street", () => {
  const matcher = new MapMatcher(makeIndex());
  matcher.process(fix(51.5, -0.0995, { time: 0 }));
  // Drifts almost exactly between the two streets. Without stickiness this is
  // a coin flip; with it, we stay on the street we were already on.
  const result = matcher.process(fix(51.50011, -0.099, { time: 2 }));
  assert.equal(result.match?.segment.id, "main");
});

test("consecutive fixes bridge the stretch between them", () => {
  const matcher = new MapMatcher(makeIndex());
  matcher.process(fix(51.5, -0.0998, { time: 0 }));
  const result = matcher.process(fix(51.5, -0.098, { time: 5 }));
  assert.ok(result.traversal, "expected a traversal");
  assert.ok(result.traversal.upper - result.traversal.lower > 0.4);
});

test("a long gap is not bridged", () => {
  const matcher = new MapMatcher(makeIndex());
  matcher.process(fix(51.5, -0.0998, { time: 0 }));
  // Five minutes later we have no idea whether the stretch between was
  // travelled, so only a small window around the fix is marked.
  const result = matcher.process(fix(51.5, -0.098, { time: 300 }));
  assert.ok(result.traversal.upper - result.traversal.lower < 0.2);
});

test("no candidates far from any street", () => {
  const matcher = new MapMatcher(makeIndex());
  assert.equal(matcher.process(fix(51.6, -0.2)).rejected, "no-candidates");
});

test("heading penalty rejects perpendicular travel", () => {
  const matcher = new MapMatcher(makeIndex());
  // Travelling due north, fast, beside an east-west street.
  const result = matcher.process(fix(51.50008, -0.099, { heading: 0, speed: 15 }));
  assert.equal(result.match, null);
});

test("a slow fix ignores its own noisy heading", () => {
  const matcher = new MapMatcher(makeIndex());
  // Same perpendicular heading, but at walking pace the course is noise, so
  // the fix should still match.
  const result = matcher.process(fix(51.50008, -0.099, { heading: 0, speed: 0.3 }));
  assert.equal(result.match?.segment.id, "main");
});

// ---------- Overpass import ----------

test("ways split at shared nodes", () => {
  const elements = [
    {
      id: 1,
      nodes: [100, 101, 102],
      geometry: [
        { lat: 51.5, lon: -0.1 },
        { lat: 51.5, lon: -0.099 },
        { lat: 51.5, lon: -0.098 },
      ],
      tags: { highway: "residential", name: "Main Street" },
    },
    {
      id: 2,
      nodes: [200, 101, 201],
      geometry: [
        { lat: 51.499, lon: -0.099 },
        { lat: 51.5, lon: -0.099 },
        { lat: 51.501, lon: -0.099 },
      ],
      tags: { highway: "residential", name: "Cross Road" },
    },
  ];
  const segments = segmentsFromElements(elements, "x");
  assert.equal(segments.filter((s) => s.name === "Main Street").length, 2);
  assert.equal(segments.filter((s) => s.name === "Cross Road").length, 2);
  assert.ok(segments.every((s) => s.length > 5));
});

test("unsupported highway types are dropped", () => {
  const elements = [{
    id: 3, nodes: [1, 2],
    geometry: [{ lat: 51.5, lon: -0.1 }, { lat: 51.5, lon: -0.099 }],
    tags: { highway: "proposed" },
  }];
  assert.equal(segmentsFromElements(elements, "x").length, 0);
});

test("segments carry a usable bounding box", () => {
  const elements = [{
    id: 4, nodes: [1, 2],
    geometry: [{ lat: 51.5, lon: -0.1 }, { lat: 51.501, lon: -0.099 }],
    tags: { highway: "residential" },
  }];
  const [segment] = segmentsFromElements(elements, "x");
  close(segment.bbox.minLat, 51.5, 1e-9);
  close(segment.bbox.maxLon, -0.099, 1e-9);
});

// ---------- Segment geometry ----------

const sample = {
  id: "s", name: "Test Street", klass: "residential", oneway: false, tile: "x",
  points: [
    { lat: 51.5, lon: -0.1 },
    { lat: 51.5, lon: -0.098 },
    { lat: 51.5, lon: -0.096 },
  ],
};
sample.length = geo.polylineLength(sample.points);

test("coordinate at fraction lands mid-segment", () => {
  close(coordinateAtFraction(sample, 0.5).lon, -0.098, 0.0002);
});

test("partial polyline stays within bounds", () => {
  const partial = subPolyline(sample, 0.25, 0.75);
  assert.ok(partial.length >= 2);
  assert.ok(partial[0].lon > -0.1);
  assert.ok(partial[partial.length - 1].lon < -0.096);
});

test("a full-span polyline covers the whole street", () => {
  const full = subPolyline(sample, 0, 1);
  close(geo.polylineLength(full), sample.length, 1);
});

// ---------- Tiles, levels, modes ----------

test("tile key contains its own coordinate", () => {
  const key = tileKey(51.507, -0.128);
  const [x, y] = key.split("_").map(Number);
  assert.ok(y * 0.02 <= 51.507 && (y + 1) * 0.02 > 51.507);
  assert.ok(x * 0.02 <= -0.128 && (x + 1) * 0.02 > -0.128);
});

test("tile neighbourhood is nine tiles", () => {
  assert.equal(tileNeighbourhood("0_0").length, 9);
  assert.equal(new Set(tileNeighbourhood("3_-2")).size, 9);
});

test("level curve is monotonic", () => {
  let previous = -1;
  for (let level = 1; level <= MAX_LEVEL; level++) {
    const required = xpRequired(level);
    assert.ok(required > previous, `level ${level} should cost more than ${level - 1}`);
    previous = required;
  }
});

test("level for XP", () => {
  assert.equal(levelForXP(0), 1);
  assert.equal(levelForXP(xpRequired(5)), 5);
  assert.equal(levelForXP(xpRequired(5) - 1), 4);
  assert.equal(levelForXP(100000000), MAX_LEVEL);
});

test("travel mode inference", () => {
  assert.equal(inferMode(1.2), "walking");
  assert.equal(inferMode(5), "cycling");
  assert.equal(inferMode(20), "driving");
  assert.equal(inferMode(-1), "unknown");
});

// ---------- Report ----------

for (const { name, error } of failures) {
  console.error(`FAIL  ${name}\n      ${error.message}`);
}
console.log(`\n${passed} passed, ${failures.length} failed`);
process.exit(failures.length ? 1 : 0);
