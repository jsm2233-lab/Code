// Display formatting, in one place so units stay consistent across screens.

export function distance(metres) {
  if (metres < 1000) return `${Math.round(metres)} m`;
  return `${(metres / 1000).toFixed(1)} km`;
}

export function duration(ms) {
  const total = Math.floor(ms / 1000);
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  if (hours > 0) return `${hours}h ${minutes}m`;
  return `${minutes}m ${total % 60}s`;
}

export function speed(metresPerSecond) {
  return `${(metresPerSecond * 3.6).toFixed(1)} km/h`;
}

export function percent(fraction) {
  return `${(Math.max(0, Math.min(1, fraction)) * 100).toFixed(1)}%`;
}

export function xp(value) {
  return Math.round(value).toLocaleString();
}

export function relative(timestamp) {
  const seconds = (Date.now() - timestamp) / 1000;
  if (seconds < 60) return "just now";
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
  if (seconds < 2592000) return `${Math.floor(seconds / 86400)}d ago`;
  return new Date(timestamp).toLocaleDateString(undefined, { month: "short", day: "numeric" });
}

export function dateTime(timestamp) {
  return new Date(timestamp).toLocaleString(undefined, {
    month: "short", day: "numeric", hour: "numeric", minute: "2-digit",
  });
}

/** Escapes text bound for innerHTML. Street names come from OSM, which anyone
 *  can edit, so they are never trusted markup. */
export function escape(text) {
  return String(text).replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])
  );
}

/** SVG progress ring, sized to fill its container. */
export function ring(fraction, { size = 42, width = 4, gradient = "ringGradient", track = "rgba(45,224,165,0.16)" } = {}) {
  const radius = (size - width) / 2;
  const circumference = 2 * Math.PI * radius;
  const dash = Math.max(0.001, Math.min(1, fraction)) * circumference;
  return `<svg viewBox="0 0 ${size} ${size}" width="${size}" height="${size}">
    <circle cx="${size / 2}" cy="${size / 2}" r="${radius}" fill="none" stroke="${track}" stroke-width="${width}"/>
    <circle cx="${size / 2}" cy="${size / 2}" r="${radius}" fill="none" stroke="url(#${gradient})"
            stroke-width="${width}" stroke-linecap="round"
            stroke-dasharray="${dash} ${circumference}"/>
  </svg>`;
}
