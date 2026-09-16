"""Generates the Street Collector app icon: a dark city grid with one lit route.

Pure stdlib. Renders at 2x and box-downsamples for anti-aliasing.
"""
import math, struct, zlib

import sys
S = int(sys.argv[2]) if len(sys.argv) > 2 else 1024
SS = 2           # supersample factor
W = S * SS

buf = bytearray(W * W * 3)

def lerp(a, b, t): return a + (b - a) * t

# Background: vertical gradient, darkest at the bottom.
top = (0x18, 0x25, 0x33)
bot = (0x07, 0x0A, 0x10)
for y in range(W):
    t = y / (W - 1)
    r = int(lerp(top[0], bot[0], t)); g = int(lerp(top[1], bot[1], t)); b = int(lerp(top[2], bot[2], t))
    row = bytes((r, g, b)) * W
    buf[y * W * 3:(y + 1) * W * 3] = row

def blend(x, y, colour, alpha):
    if alpha <= 0 or x < 0 or y < 0 or x >= W or y >= W:
        return
    if alpha > 1: alpha = 1.0
    i = (y * W + x) * 3
    for k in range(3):
        buf[i + k] = min(255, int(buf[i + k] * (1 - alpha) + colour[k] * alpha))

def line(p0, p1, width, colour, alpha):
    """Anti-aliased thick segment via distance field over its bounding box."""
    x0, y0 = p0; x1, y1 = p1
    dx, dy = x1 - x0, y1 - y0
    length_sq = dx * dx + dy * dy
    half = width / 2
    pad = int(half) + 2
    for py in range(max(0, int(min(y0, y1)) - pad), min(W, int(max(y0, y1)) + pad)):
        for px in range(max(0, int(min(x0, x1)) - pad), min(W, int(max(x0, x1)) + pad)):
            if length_sq == 0:
                d = math.hypot(px - x0, py - y0)
            else:
                t = max(0, min(1, ((px - x0) * dx + (py - y0) * dy) / length_sq))
                d = math.hypot(px - (x0 + t * dx), py - (y0 + t * dy))
            edge = half - d
            if edge <= -1:
                continue
            blend(px, py, colour, alpha * max(0.0, min(1.0, edge + 0.5)))

K = S / 1024.0   # everything below is authored at 1024 and scaled

def glow_line(p0, p1, colour, core, alpha=1.0):
    core = core * K
    """Neon: wide haze, mid bloom, bright core, white centre."""
    for width, a in ((core * 5.0, 0.055 * alpha), (core * 2.8, 0.13 * alpha), (core * 1.6, 0.3 * alpha)):
        line(p0, p1, width * SS, colour, a)
    line(p0, p1, core * SS, colour, 0.98 * alpha)
    line(p0, p1, core * 0.3 * SS, (255, 255, 255), 0.75 * alpha)

def dim_line(p0, p1, core):
    line(p0, p1, core * K * SS, (0x55, 0x66, 0x78), 0.42)

U = W / 9.0   # grid unit
def P(cx, cy): return (cx * U, cy * U)

# --- The dim grid: an ordinary street plan, deliberately irregular.
# Bled off every edge: an icon is a window onto a city, not a diagram of one.
verticals = [1.3, 3.0, 4.6, 6.2, 7.8]
horizontals = [1.4, 3.1, 4.7, 6.3, 7.9]
for x in verticals:
    dim_line(P(x, -0.4), P(x, 9.4), 9)
for y in horizontals:
    dim_line(P(-0.4, y), P(9.4, y), 9)

MINT = (0x2D, 0xE0, 0xA5)
CYAN = (0x5B, 0xC8, 0xFF)

# --- The collected route: a turning path through the grid, lit end to end.
route = [
    P(1.3, 8.6), P(1.3, 6.3), P(4.6, 6.3), P(4.6, 3.1), P(7.8, 3.1), P(7.8, 1.4),
]
for i in range(len(route) - 1):
    # Fades from cyan at the start to mint at the head: the route has direction.
    t = i / (len(route) - 2)
    colour = tuple(int(lerp(CYAN[k], MINT[k], t)) for k in range(3))
    glow_line(route[i], route[i + 1], colour, 26)

# --- The player: a glowing dot at the head of the route.
hx, hy = route[-1]
for radius, a in ((150, 0.10), (96, 0.18), (58, 0.40)):
    line((hx, hy), (hx, hy), radius * K * SS, MINT, a)
line((hx, hy), (hx, hy), 40 * K * SS, MINT, 1.0)
line((hx, hy), (hx, hy), 17 * K * SS, (255, 255, 255), 0.95)

# --- Downsample and write.
out = bytearray(S * S * 3)
for y in range(S):
    for x in range(S):
        r = g = b = 0
        for oy in range(SS):
            base = ((y * SS + oy) * W + x * SS) * 3
            for ox in range(SS):
                r += buf[base + ox * 3]; g += buf[base + ox * 3 + 1]; b += buf[base + ox * 3 + 2]
        n = SS * SS
        i = (y * S + x) * 3
        out[i] = r // n; out[i + 1] = g // n; out[i + 2] = b // n

raw = bytearray()
for y in range(S):
    raw.append(0)
    raw += out[y * S * 3:(y + 1) * S * 3]

def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

png = (b"\x89PNG\r\n\x1a\n"
       + chunk(b"IHDR", struct.pack(">IIBBBBB", S, S, 8, 2, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
       + chunk(b"IEND", b""))

open(sys.argv[1] if len(sys.argv) > 1 else "icon-1024.png", "wb").write(png)
print("wrote", sys.argv[1], len(png), "bytes")
