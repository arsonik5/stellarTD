# 01 - Vision: what Stellar TD is

Decided with Michael 2026-11-04. This file is the root every other design decision answers to. If a mechanic
cannot be traced back to a line here, it does not belong in the game yet.

## Premise

Earth broke. A slow cataclysm (working name: **the Severance**) left the home world unable to feed or power
what is left of humanity. The survivors pooled everything into one programme (working name: **the Continuance**):
send lone, heavily equipped operators - **Voyagers** - out to other worlds to research them, extract what Earth
needs, build, and prepare the ground for colonies that robots will eventually run.

You are a Voyager. You land on a world with a seed kit, a drill and a contract. Nobody is coming to help, the
Continuance only talks to you through the uplink, and the reason worlds like this are worth the trip - the
radioactive **crystal** - is also what wakes the things that live between the stars.

Tone: industrial, lonely, competent. Corporate-contract structure, but the contract is a lifeline, not a joke.
Explicitly NOT Satisfactory's lore (no comedic megacorp, no "efficiency" satire). Closer to a wartime
reconstruction effort: rationed, earnest, a little desperate.

> Names (Severance, Continuance, Voyager) are placeholders. Change them in one place: this file.

## The fantasy in one line

**Arrive alone on a vast world, turn it into an automated outpost that feeds a dying Earth, and hold it against
what your success attracts.**

## Pillars (in priority order - when two conflict, the higher one wins)

1. **The world is the resource.** Big SE2-scale planets you can dig into. Prospecting with your own eyes and
   tools, then carving real holes, is the base of everything. Planets must be worth looking at and worth
   travelling across (No Man's Sky appetite).
2. **Build it once, then automate it.** Everything you do by hand early (drill, carry, craft, defend) becomes a
   machine, then a network, then a robot's job. Progress is measured in what you no longer have to do yourself.
3. **Success has a price.** Output, power and especially crystal raise your **signature**. Signature draws
   threat. Threat is the TD half: it scales with your ambition, never with a clock. Staying quiet is a valid
   strategy; growing loud must be survivable with preparation.
4. **Everything is physical.** Projectiles fly, ships have mass and thrust, wheels have suspension, holes stay
   dug, items travel through pipes. No hitscan economy, no teleporting goods (late-game exceptions must be earned
   and expensive).
5. **Every action answers back.** Hover, press, confirm, error, mined, crafted, hit - each has a visible and an
   audible response (see `ux-bible.md`). A mechanic without feedback is not finished.

## Shape of a playthrough: endless, but with arcs

No win screen. The Continuance keeps issuing **Directives** (contracts) forever, scaling with what you have
proven you can do. Structure comes from **arcs**, each a tier that changes how you play:

| Arc | You are... | Typical tools | Threat tier |
|---|---|---|---|
| 1. Landfall | surviving and learning the world | hand drill, scanner, first processor, suit O2 | none |
| 2. Outpost | running a small automated base | deposit drills, pipes, smelters, power, first turrets | scouts |
| 3. Expansion | reaching remote deposits on your planet | buggies, haulers, remote outposts, relay power | gunship raids |
| 4. Orbit | leaving the planet | ships, moon/asteroid mining, uplink launches | dropships + raids |
| 5. Colony | directing robots, not doing labour | drones, robot crews, colony modules | sieges, bombardment |

Arcs are unlocked by research and Directives, not by time. A player can stay in arc 2 forever if they keep the
signature low.

## What the game is NOT (scope guards)

- Not a survival-crafting hunger/thirst sim. Suit oxygen and hazards exist to give the world teeth, not chores.
- Not multiplayer-first (designed not to block it - deterministic sim - but solo is the target).
- Not a story game. Lore lives in Directive text, logs, wrecks and the uplink. No cutscenes.
- Not an FPS. The player can defend themselves late, but turrets, ships and base design win fights.
- No fauna in 1.0 (aliens are ships/drones). Passive wildlife is a post-1.0 NMS-style option, see `05-planets.md`.
