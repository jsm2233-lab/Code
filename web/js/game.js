// Scoring, levelling, streaks and badges. Ports PlayerProfile.swift,
// Achievement.swift and GameEngine.swift.

import { prefs } from "./store.js";
import { CLASS_INFO, displayName } from "./streets.js";

export const MAX_LEVEL = 60;

// Quadratic curve: early levels come fast, later ones take real exploring.
export function xpRequired(level) {
  if (level <= 1) return 0;
  const n = level - 1;
  return Math.round(120 * n * n + 380 * n);
}

export function levelForXP(xp) {
  let level = 1;
  while (level < MAX_LEVEL && xp >= xpRequired(level + 1)) level++;
  return level;
}

export function levelTitle(level) {
  if (level < 5) return "Lost Tourist";
  if (level < 10) return "Wanderer";
  if (level < 16) return "Pathfinder";
  if (level < 23) return "Street Sweeper";
  if (level < 31) return "Cartographer";
  if (level < 40) return "District Warden";
  if (level < 50) return "City Runner";
  if (level < 60) return "Grid Master";
  return "Every Street";
}

export const TIER_XP = { bronze: 250, silver: 750, gold: 2000, legendary: 6000 };

export const ACHIEVEMENTS = [
  { id: "first.street", title: "First Blood", detail: "Collect your first street.", icon: "🚩", tier: "bronze", target: 1, kind: "segments" },
  { id: "streets.25", title: "Getting Somewhere", detail: "Collect 25 streets.", icon: "🗺️", tier: "bronze", target: 25, kind: "segments" },
  { id: "streets.100", title: "Local Knowledge", detail: "Collect 100 streets.", icon: "🏘️", tier: "silver", target: 100, kind: "segments" },
  { id: "streets.500", title: "The Knowledge", detail: "Collect 500 streets.", icon: "🧠", tier: "gold", target: 500, kind: "segments" },
  { id: "streets.2000", title: "Street Sovereign", detail: "Collect 2,000 streets.", icon: "👑", tier: "legendary", target: 2000, kind: "segments" },

  { id: "newkm.10", title: "Ten Fresh", detail: "Cover 10 km of streets you'd never been down.", icon: "✨", tier: "bronze", target: 10, kind: "newKm" },
  { id: "newkm.100", title: "Century of the New", detail: "Cover 100 km of new streets.", icon: "🛣️", tier: "silver", target: 100, kind: "newKm" },
  { id: "newkm.1000", title: "Four Figures", detail: "Cover 1,000 km of new streets.", icon: "🌍", tier: "gold", target: 1000, kind: "newKm" },

  { id: "streak.3", title: "Warming Up", detail: "Collect something new three days running.", icon: "🔥", tier: "bronze", target: 3, kind: "streak" },
  { id: "streak.14", title: "Fortnight", detail: "Fourteen-day collecting streak.", icon: "🔥", tier: "silver", target: 14, kind: "streak" },
  { id: "streak.60", title: "Obsessive", detail: "Sixty-day collecting streak.", icon: "🔥", tier: "legendary", target: 60, kind: "streak" },

  { id: "tile.50", title: "Half a Neighbourhood", detail: "Reach 50% coverage in any one area.", icon: "🔲", tier: "silver", target: 50, kind: "tile" },
  { id: "tile.100", title: "Clean Sweep", detail: "Fully clear an area. Every single street.", icon: "🏅", tier: "legendary", target: 100, kind: "tile" },

  { id: "trip.newkm.5", title: "Deliberate Detour", detail: "Cover 5 km of new streets in one trip.", icon: "🔀", tier: "bronze", target: 5, kind: "tripNewKm" },
  { id: "trip.newkm.25", title: "Expedition", detail: "Cover 25 km of new streets in one trip.", icon: "🥾", tier: "gold", target: 25, kind: "tripNewKm" },

  { id: "named.250", title: "Name Dropper", detail: "Collect 250 distinctly named streets.", icon: "🔤", tier: "silver", target: 250, kind: "named" },
  { id: "night.50", title: "Night Shift", detail: "Collect 50 streets between midnight and 5am.", icon: "🌙", tier: "gold", target: 50, kind: "night" },
  { id: "walk.50", title: "On Foot", detail: "Collect 50 km of streets walking.", icon: "🚶", tier: "silver", target: 50, kind: "walkKm" },
];

const XP_PER_NEW_METRE = 0.1;
const COMPLETION_BONUS = 40;

export function emptyProfile() {
  return {
    xp: 0,
    totalDistance: 0,
    totalNewStreetMetres: 0,
    segmentsCompleted: 0,
    currentStreak: 0,
    longestStreak: 0,
    lastCollectionDay: null,
    unlocked: [],
    homeTile: null,
  };
}

export class Game extends EventTarget {
  constructor() {
    super();
    this.profile = { ...emptyProfile(), ...prefs.get("profile", {}) };
    this.recentEvents = [];
    this.refreshStreak();
  }

  get level() {
    return levelForXP(this.profile.xp);
  }

  get levelProgress() {
    const level = this.level;
    const floor = xpRequired(level);
    const ceiling = xpRequired(level + 1);
    return ceiling > floor ? (this.profile.xp - floor) / (ceiling - floor) : 1;
  }

  get xpIntoLevel() {
    return this.profile.xp - xpRequired(this.level);
  }

  get xpForNextLevel() {
    return xpRequired(this.level + 1) - xpRequired(this.level);
  }

  /** Scores one coverage delta. Returns the XP awarded. */
  award(delta, mode, time) {
    const info = CLASS_INFO[delta.segment.klass];
    let xp = delta.newMetres * XP_PER_NEW_METRE * info.multiplier;

    if (delta.completedNow) xp += COMPLETION_BONUS * info.multiplier;
    // Walking a street is slower and more deliberate than driving it.
    if (mode === "walking") xp *= 1.25;
    // Late-night collecting is its own small reward.
    if (new Date(time).getHours() < 5) xp *= 1.15;

    const awarded = Math.round(xp);
    if (awarded <= 0) return 0;

    const levelBefore = this.level;
    this.profile.xp += awarded;
    this.profile.totalNewStreetMetres += delta.newMetres;

    if (delta.completedNow) {
      this.profile.segmentsCompleted += 1;
      this._pushEvent({ title: displayName(delta.segment), xp: awarded, icon: "✅" });
    }

    if (this.level > levelBefore) {
      this.celebrate({ kind: "level", level: this.level, title: levelTitle(this.level) });
    }

    this._updateStreak(time);
    this.save();
    return awarded;
  }

  addDistance(metres) {
    if (metres > 0) this.profile.totalDistance += metres;
  }

  setHomeTile(tile) {
    if (!this.profile.homeTile) {
      this.profile.homeTile = tile;
      this.save();
    }
  }

  _updateStreak(time) {
    const today = startOfDay(new Date(time));
    const last = this.profile.lastCollectionDay ? startOfDay(new Date(this.profile.lastCollectionDay)) : null;

    if (!last) {
      this.profile.currentStreak = 1;
      this.profile.longestStreak = Math.max(1, this.profile.longestStreak);
      this.profile.lastCollectionDay = today.toISOString();
      return;
    }
    if (today.getTime() === last.getTime()) return;

    const days = Math.round((today - last) / 86400000);
    this.profile.currentStreak = days === 1 ? this.profile.currentStreak + 1 : 1;
    this.profile.longestStreak = Math.max(this.profile.longestStreak, this.profile.currentStreak);
    this.profile.lastCollectionDay = today.toISOString();
  }

  /** Streaks decay in real time, not just when you collect, so the HUD can't
   *  claim a 12-day streak you broke last Tuesday. */
  refreshStreak(now = new Date()) {
    if (!this.profile.lastCollectionDay) return;
    const last = startOfDay(new Date(this.profile.lastCollectionDay));
    const days = Math.round((startOfDay(now) - last) / 86400000);
    if (days > 1 && this.profile.currentStreak !== 0) {
      this.profile.currentStreak = 0;
      this.save();
    }
  }

  /**
   * Recomputes every badge from current state. Cheap enough to run after each
   * trip, and it means new badges credit past play.
   */
  evaluate(stats) {
    const unlocked = [];
    for (const achievement of ACHIEVEMENTS) {
      if (this.profile.unlocked.includes(achievement.id)) continue;
      if (progressValue(achievement, stats, this.profile) >= achievement.target) {
        this.profile.unlocked.push(achievement.id);
        this.profile.xp += TIER_XP[achievement.tier];
        unlocked.push(achievement);
        this._pushEvent({ title: achievement.title, xp: TIER_XP[achievement.tier], icon: achievement.icon });
      }
    }
    if (unlocked.length) {
      // A badge outranks a level-up for the celebration slot: it's rarer and it
      // has something to say.
      const last = unlocked[unlocked.length - 1];
      this.celebrate({ kind: "badge", achievement: last });
      this.save();
    }
    return unlocked;
  }

  progressList(stats) {
    return ACHIEVEMENTS.map((achievement) => {
      const value = progressValue(achievement, stats, this.profile);
      return {
        achievement,
        value,
        unlocked: this.profile.unlocked.includes(achievement.id),
        fraction: achievement.target > 0 ? Math.min(1, value / achievement.target) : 0,
      };
    });
  }

  celebrate(payload) {
    this.dispatchEvent(new CustomEvent("celebrate", { detail: payload }));
  }

  _pushEvent(event) {
    event.time = Date.now();
    this.recentEvents.push(event);
    if (this.recentEvents.length > 8) this.recentEvents.splice(0, this.recentEvents.length - 8);
    this.dispatchEvent(new CustomEvent("score", { detail: event }));
  }

  expireEvents(maxAge = 4000) {
    const cutoff = Date.now() - maxAge;
    const before = this.recentEvents.length;
    this.recentEvents = this.recentEvents.filter((e) => e.time >= cutoff);
    return this.recentEvents.length !== before;
  }

  save() {
    prefs.set("profile", this.profile);
  }

  reset() {
    this.profile = emptyProfile();
    this.recentEvents = [];
    this.save();
  }
}

function progressValue(achievement, stats, profile) {
  switch (achievement.kind) {
    case "segments": return stats.completedCount;
    case "newKm": return profile.totalNewStreetMetres / 1000;
    case "streak": return profile.currentStreak;
    case "tile": return stats.bestTilePercent;
    case "tripNewKm": return stats.bestTripNewMetres / 1000;
    case "named": return stats.distinctNamedCount;
    case "night": return stats.nightCount;
    case "walkKm": return stats.walkingNewMetres / 1000;
    default: return 0;
  }
}

function startOfDay(date) {
  const copy = new Date(date);
  copy.setHours(0, 0, 0, 0);
  return copy;
}
