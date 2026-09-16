// Uniform-grid index over street segments. Port of SpatialIndex.swift.
//
// The matcher runs on every position update against tens of thousands of
// polylines, so a linear scan is out.

// ~0.0025 deg is roughly 275 m north-south: comfortably longer than any
// segment after splitting at intersections, which keeps per-segment cell
// lists short.
const CELL_SIZE = 0.0025;

export class SpatialIndex {
  constructor() {
    this.cells = new Map();
    this.segments = new Map();
  }

  get size() {
    return this.segments.size;
  }

  get(id) {
    return this.segments.get(id);
  }

  insert(segment) {
    if (this.segments.has(segment.id)) return;
    this.segments.set(segment.id, segment);
    for (const key of this._cellKeys(segment.bbox)) {
      let bucket = this.cells.get(key);
      if (!bucket) this.cells.set(key, (bucket = []));
      bucket.push(segment.id);
    }
  }

  insertAll(segments) {
    for (const segment of segments) this.insert(segment);
  }

  removeTile(tileKey) {
    const doomed = [...this.segments.values()].filter((s) => s.tile === tileKey);
    if (!doomed.length) return;
    const ids = new Set(doomed.map((s) => s.id));
    for (const segment of doomed) this.segments.delete(segment.id);
    for (const segment of doomed) {
      for (const key of this._cellKeys(segment.bbox)) {
        const bucket = this.cells.get(key);
        if (!bucket) continue;
        const kept = bucket.filter((id) => !ids.has(id));
        if (kept.length) this.cells.set(key, kept);
        else this.cells.delete(key);
      }
    }
  }

  clear() {
    this.cells.clear();
    this.segments.clear();
  }

  /** Every segment whose bounding box comes within `radius` metres. */
  candidates(point, radius) {
    const dLat = radius / 111320;
    const dLon = radius / Math.max(1, 111320 * Math.cos((point.lat * Math.PI) / 180));

    const x0 = Math.floor((point.lon - dLon) / CELL_SIZE);
    const x1 = Math.floor((point.lon + dLon) / CELL_SIZE);
    const y0 = Math.floor((point.lat - dLat) / CELL_SIZE);
    const y1 = Math.floor((point.lat + dLat) / CELL_SIZE);

    const seen = new Set();
    const result = [];
    for (let x = x0; x <= x1; x++) {
      for (let y = y0; y <= y1; y++) {
        const bucket = this.cells.get(`${x}:${y}`);
        if (!bucket) continue;
        for (const id of bucket) {
          if (seen.has(id)) continue;
          seen.add(id);
          const segment = this.segments.get(id);
          if (!segment) continue;
          const box = segment.bbox;
          if (
            point.lat >= box.minLat - dLat &&
            point.lat <= box.maxLat + dLat &&
            point.lon >= box.minLon - dLon &&
            point.lon <= box.maxLon + dLon
          ) {
            result.push(segment);
          }
        }
      }
    }
    return result;
  }

  /** Segments intersecting a lat/lon box, for drawing the viewport. */
  inBounds(minLat, minLon, maxLat, maxLon) {
    const result = [];
    const x0 = Math.floor(minLon / CELL_SIZE);
    const x1 = Math.floor(maxLon / CELL_SIZE);
    const y0 = Math.floor(minLat / CELL_SIZE);
    const y1 = Math.floor(maxLat / CELL_SIZE);
    const seen = new Set();

    for (let x = x0; x <= x1; x++) {
      for (let y = y0; y <= y1; y++) {
        const bucket = this.cells.get(`${x}:${y}`);
        if (!bucket) continue;
        for (const id of bucket) {
          if (seen.has(id)) continue;
          seen.add(id);
          const segment = this.segments.get(id);
          if (!segment) continue;
          const b = segment.bbox;
          if (b.maxLat >= minLat && b.minLat <= maxLat && b.maxLon >= minLon && b.minLon <= maxLon) {
            result.push(segment);
          }
        }
      }
    }
    return result;
  }

  tileSegments(tileKey) {
    return [...this.segments.values()].filter((s) => s.tile === tileKey);
  }

  _cellKeys(box) {
    const keys = [];
    const x0 = Math.floor(box.minLon / CELL_SIZE);
    const x1 = Math.floor(box.maxLon / CELL_SIZE);
    const y0 = Math.floor(box.minLat / CELL_SIZE);
    const y1 = Math.floor(box.maxLat / CELL_SIZE);
    for (let x = x0; x <= x1; x++) for (let y = y0; y <= y1; y++) keys.push(`${x}:${y}`);
    return keys;
  }
}
