// A normalised set of non-overlapping intervals in 0..1, tracking which
// fraction of a street has actually been travelled. Port of IntervalSet.swift.
//
// Stored as a flat array of [lo, hi] pairs, kept sorted and merged, so covered
// fraction is just a sum.

const EPSILON = 1e-4;

export function coveredFraction(intervals) {
  let total = 0;
  for (const [lo, hi] of intervals) total += Math.max(0, hi - lo);
  return Math.min(1, total);
}

/** Returns a new interval list with [lower, upper] merged in. */
export function insert(intervals, lower, upper) {
  let lo = Math.max(0, Math.min(1, Math.min(lower, upper)));
  let hi = Math.max(0, Math.min(1, Math.max(lower, upper)));
  // Sub-metre slivers are noise, not coverage.
  if (hi - lo <= EPSILON) return intervals;

  const merged = [];
  let inserted = false;

  for (const interval of intervals) {
    if (interval[1] < lo - EPSILON) {
      merged.push(interval);
    } else if (interval[0] > hi + EPSILON) {
      if (!inserted) {
        merged.push([lo, hi]);
        inserted = true;
      }
      merged.push(interval);
    } else {
      lo = Math.min(lo, interval[0]);
      hi = Math.max(hi, interval[1]);
    }
  }

  if (!inserted) merged.push([lo, hi]);
  merged.sort((a, b) => a[0] - b[0]);
  return merged;
}
