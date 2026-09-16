// Canvas confetti for the celebration overlay.
//
// One canvas drawing every particle, rather than a few hundred DOM nodes —
// the difference between smooth and a slideshow on an older phone.

const PALETTE = ["#2de0a5", "#5bc8ff", "#ffbc3d", "#ff5da2", "#a86bf5"];

export function burst(canvas, { count = 90, duration = 3200 } = {}) {
  const ctx = canvas.getContext("2d");
  const dpr = window.devicePixelRatio || 1;
  const width = canvas.clientWidth;
  const height = canvas.clientHeight;
  canvas.width = width * dpr;
  canvas.height = height * dpr;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

  const particles = Array.from({ length: count }, () => ({
    x: Math.random() * width,
    y: -30 - Math.random() * height * 0.4,
    vy: 120 + Math.random() * 180,       // px per second
    drift: (Math.random() - 0.5) * 90,
    spin: (Math.random() - 0.5) * 10,
    size: 5 + Math.random() * 6,
    colour: PALETTE[Math.floor(Math.random() * PALETTE.length)],
    phase: Math.random() * Math.PI * 2,
  }));

  const start = performance.now();
  let frame = null;

  function step(now) {
    const elapsed = now - start;
    if (elapsed > duration) {
      ctx.clearRect(0, 0, width, height);
      return;
    }
    const t = elapsed / 1000;
    ctx.clearRect(0, 0, width, height);

    for (const p of particles) {
      const y = p.y + p.vy * t;
      const x = p.x + Math.sin(t * 2 + p.phase) * p.drift;
      if (y > height + 40) continue;

      // Fade over the last third so they don't pile up at the bottom edge.
      const progress = elapsed / duration;
      ctx.globalAlpha = progress > 0.66 ? Math.max(0, (1 - progress) * 3) : 1;

      ctx.save();
      ctx.translate(x, y);
      ctx.rotate(t * p.spin + p.phase);
      ctx.fillStyle = p.colour;
      ctx.fillRect(-p.size / 2, -p.size / 2, p.size, p.size * 1.6);
      ctx.restore();
    }
    ctx.globalAlpha = 1;
    frame = requestAnimationFrame(step);
  }

  frame = requestAnimationFrame(step);
  return () => {
    if (frame) cancelAnimationFrame(frame);
    ctx.clearRect(0, 0, width, height);
  };
}
