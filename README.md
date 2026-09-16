# Street Collector

An iPhone app that fills in every street you go down, in real time. The city
starts dark; each street you travel lights up and stays lit. The goal is to
collect all of them.

Built with SwiftUI, MapKit and Core Location. Street geometry comes from
OpenStreetMap via the Overpass API. No backend, no account, no data leaves the
phone except the map queries themselves.

## How it works

The interesting part is turning a stream of noisy GPS fixes into "you have now
been down 68% of Baker Street".

1. **Street data.** `OverpassClient` pulls every `highway` way in a 0.02°
   tile and splits each way at nodes shared with another way, so a segment is
   always intersection-to-intersection. Without that split, "collecting a
   street" would mean wildly different amounts of travel depending on how OSM
   happened to chop the way up. Tiles are cached on disk for a fortnight, and a
   stale cache is used if the network is gone.

2. **Indexing.** `SpatialIndex` is a uniform grid over segment bounding boxes.
   The matcher runs on every location update against tens of thousands of
   polylines, so a linear scan is out.

3. **Matching.** `MapMatcher` scores each nearby segment on three things:
   perpendicular distance, how well the fix's course agrees with the road's
   bearing, and stickiness toward the segment matched last. Stickiness is what
   stops the match flickering between a road and the cycle path beside it;
   the heading term is what stops a dual carriageway collecting both
   directions at once.

4. **Coverage.** Two consecutive fixes on the same segment prove the stretch
   between them was travelled, so `IntervalSet` records `[t₀, t₁]` as a merged
   interval in 0...1. A single isolated fix only marks a small window around
   itself. A segment counts as collected at 70% — GPS drops out under bridges,
   and demanding 100% would make long streets feel broken.

5. **Scoring.** XP per metre of *new* street, weighted by road class:
   residential backstreets pay 1.4×, motorway 0.5×, because the point is
   exploring the fiddly bits. Finishing a segment end to end pays a bonus.
   Walking pays 1.25×, collecting after midnight 1.15×.

## Look

The app is a game about a city at night, and it's built to read that way.

- **One dark palette, three signal colours.** Mint means collected, amber means
  in progress, cyan means happening right now. Nothing else is allowed to use
  them. Everything is set in SF Rounded — the cheapest single decision that
  stops a map app reading as a spreadsheet.
- **Neon streets.** Collected streets are drawn as three stacked strokes — a
  wide haze, a mid bloom, a bright core — which fakes a convincing neon glow at
  a fraction of the cost of a real blur. Finished streets get a white-hot centre
  line so they're unmistakable from nearly-finished ones. Uncollected streets
  are barely there: a suggestion of a grid waiting to be lit.
- **Fog of war** dims everywhere you haven't been and cuts a soft-edged corridor
  along everywhere you have, by stacking destination-out strokes at decreasing
  width and increasing opacity.
- **The player dot** is a mint core with a halo that breathes while a trip is
  running, replacing MapKit's blue dot.
- **Celebrations** for level-ups and badges: a `Canvas`-drawn confetti burst (one
  canvas, ~90 particles, not 90 SwiftUI views) behind a gradient medal. Always
  tap-to-dismiss and auto-closing after 4.5s, because this fires while people are
  driving.
- **Badges** are gradient-filled and glowing when unlocked, desaturated with
  visible progress when not, and shimmer once they pass 75% — the "nearly there"
  nudge, applied to nothing else.

The app icon is generated procedurally by a stdlib-only Python script
(`scripts/make_icon.py`): a lit route turning through a dim street grid, in the
same palette.

## Features

- Live map with collected streets lit, partial progress in amber, and an
  optional fog-of-war layer that darkens everywhere you haven't been.
- Background collection — start a trip, pocket the phone, keep collecting.
- Levels (60 of them, quadratic curve), daily streaks, and 18 badges across
  four tiers. Badge progress is recomputed from state, so new badges credit
  past play.
- Per-area completion rings, a 30-day activity chart, trip history with
  per-trip maps and stats.
- "Collect next": nearby streets you haven't finished, closest first.
- Collection book: every street you've touched, grouped by name, searchable.
- Export collected streets as GeoJSON, individual trips as GPX.

## Building

Needs Xcode 15+ and an iOS 17 deployment target. The Xcode project is generated
rather than committed, so there's no `.pbxproj` to fight over in diffs:

```sh
brew install xcodegen
make open        # generates StreetCollector.xcodeproj and opens it
make test        # runs the unit tests on a simulator
```

Set your development team in Xcode before running on a device. Background
location needs a real device — the simulator's location doesn't behave like a
GPS.

### Building without a Mac

There is no Swift compiler on iOS, so the build has to happen on a macOS
runner. `.github/workflows/ci.yml` generates the project and runs the tests on
every push, and can be triggered by hand from github.com in mobile Safari
(Actions → Build → Run workflow). Failures are readable in the job log from a
phone; that is the edit-compile-read-errors loop without a Mac in it.

Note that macOS runner minutes bill at 10x on private repos, so a free-plan
account gets roughly 200 minutes of macOS a month. Each run is a few minutes.

Getting the app *onto* a phone is a separate problem, and CI can't solve it
without signing material: installing requires a signed build, which requires a
paid Apple Developer account. With one, add the distribution certificate and
provisioning profile as repository secrets, sign in the workflow and upload to
TestFlight — after that one-time setup, pushing a commit from a phone ends with
a new build appearing in TestFlight on the same phone. The setup itself
realistically wants a desktop.

### Permissions

The app asks for location "Always" (background collection is the whole point)
and, optionally, notifications. Precise location is required: with reduced
accuracy on, there's no way to tell which of two parallel streets you're on,
and the app tells the user as much in Settings.

## Layout

```
StreetCollector/
  App/         composition root, settings, tab shell
  Models/      Coordinate, StreetSegment, Trip, Achievement, PlayerProfile
  Core/        GeoMath, IntervalSet, SpatialIndex, MapMatcher
  Services/    location, Overpass, stores, game engine, export
  Views/       map + overlay renderers, stats, badges, trips, settings
StreetCollectorTests/
```

`Core/` is pure and has no UIKit or Core Location dependencies beyond
`CLLocation` itself, which is what makes the matcher testable without a device.

## Known limits

- Overpass is a donated public service. Requests are throttled to one every
  1.2s with endpoint rotation on failure. A dedicated instance or a
  pre-processed vector extract would be the move for real distribution.
- Areas are 0.02° tiles, not real neighbourhoods. Proper admin boundaries would
  need another dataset.
- Coverage and trips are stored as JSON blobs. That's fine into the tens of
  thousands of segments; past that it wants SQLite with a spatial index.
- No sync, no backup, no leaderboards. Everything is local to the device.

Map data © OpenStreetMap contributors, ODbL.
