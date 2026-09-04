# Radiation/Crystal Threat System — design + scopes

Source of truth for this system's lore and mechanics. `gamebrief.md` tracks
overall slice scope; this file is the detail behind Slice 2's wave/threat
design specifically. Update on material changes, same convention as
`gamebrief.md`.

## Lore

Player is a corporate mining operation. The objective ore is a radioactive
crystal with two uses:
- **Direct use** — socketed into base systems (reactor fuel, weapon cores,
  high-tier building material). Stays in inventory/storage, so it produces a
  small but *persistent* signature for as long as it's held.
- **Dissolve** — a dedicated machine converts it into the actual mission
  resource corporate wants. Running it produces a large but *temporary*
  signature spike, then quiet during cooldown. (Not built yet — see Scope 4.)

The crystal's signature is what draws attention. All enemies are alien
**starships**, not ground troops — they arrive from beyond the system and
approach the planet. There is currently no ground-combat enemy type planned;
this is a deliberate scope decision, not an oversight.

## Threat tiers (signature-driven, no arbitrary clock)

| Tier | Signature | Behavior |
|---|---|---|
| **None** | ~0 | No spawns. Staying at zero signature is a legitimate playstyle, not a loss condition. |
| **Low** | small, sustained leak | A single scout ship flies in, hovers near the source, and scans. If it detects something (chance scales with how deep into this band the signature sits), it turns and flees toward system edge to report. **If it reaches the edge, a larger fleet arrives after a delay. If the player destroys it before it escapes, the report never goes out and nothing escalates** — this is the core tension of the tier: hunt the scout down in the open, or let it slip past your defenses. |
| **High** | large/sustained | No scout, no round-trip — the mothership detects the source directly and puts the player into a constant, ongoing war state (continuous fleet pressure, no cooldown) until signature is brought back down. |

Signature is driven by (a) crystal currently held/socketed (persistent) and
(b) dissolve-machine bursts (temporary spike) once that machine exists.
Barriers/containment (Scope 5) are the tool that brings signature back down
a tier without simply not mining the crystal at all.

## Scopes

Each scope is a standalone, independently testable increment. Don't start a
later scope before the current one is validated (headless smoke test +
playtest), per this repo's staged-slice discipline.

**Scope 1 — Signature foundation + the scout ship (current)**
- New `Radioactive Crystal` ore (rare terrain vein, same pattern as the
  existing 5 ores) and item.
- `RadiationSignature` autoload: signature value derived from crystal
  currently held, tier enum (None/Low/High), `tier_changed` signal.
- `ThreatDirector`: on entering Low tier (with a cooldown so it can't spam),
  spawns one scout ship near the target planet.
- Scout ship: flies in from system edge, hovers/scans near the source for a
  duration, rolls detection, then either flees silently (nothing found) or
  flees while broadcasting a report (found something). Targetable by
  existing turrets with zero turret-side changes (same `"enemy"` group +
  `take_damage()` contract every enemy already uses).
- Reaching system edge while carrying a report fires a `leak_reported`
  signal — currently just logged as an escalation stub. **The actual bigger
  fleet is Scope 2, not part of this scope.**
- Out of scope for Scope 1: dissolve machine, barriers, High tier behavior,
  actual combat balance/tuning.

**Scope 2 — The escalation fleet**
- What `leak_reported` actually spawns: a multi-ship fleet that engages the
  base rather than just scanning and leaving.
- Open design question to resolve before starting this scope: how do
  starships actually damage a *ground* base — orbital bombardment (ranged
  AoE from altitude), landing/boarding, or low-altitude gunship behavior
  (descend into turret range and slug it out)? Needs a decision, not an
  assumption, since it drives whether ground turrets alone can ever answer
  a fleet or whether anti-orbital defense is mandatory from this scope on.

**Scope 3 — High tier / constant war state**
- Mothership-driven continuous spawning once signature crosses into High,
  no scout/round-trip, no cooldown between waves — sustained pressure until
  the player brings signature back down.

**Scope 4 — Dissolve machine**
- New building: converts raw crystal into the mission resource, on a
  discrete run (not continuous), producing the temporary signature-spike
  half of the signature model described above. This is also the natural
  place to hang corporate "contracts" (quest system) — a contract sets a
  quota of dissolved resource, and choosing when to run the dissolver is
  the player's own opt-in escalation trigger.

**Scope 5 — Containment / barriers**
- Placed building that dampens signature radius while powered. Ties into
  the planned power grid (`gamebrief.md`'s Slice 2 "power grid = attack
  surface" line) — losing power to the dampener is a real containment
  breach, not just a soft debuff.
- Natural target for the "enemies path toward the weakest link" raid
  behavior once ground-adjacent combat exists (Scope 2's open question).

**Later, not yet scoped**: anti-orbital turret tier, corporate contract/quest
UI, per-planet crystal variance (richer on some planets, rarer on others —
ties into the existing multi-planet architecture), faction/lore framing for
*why* the aliens are protecting this crystal.
