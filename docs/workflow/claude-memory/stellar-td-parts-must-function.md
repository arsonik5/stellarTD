---
name: stellar-td-parts-must-function
description: "Michael's top rule for Stellar TD models - every part, bolt and detail must make mechanical sense; random parts are the biggest telltale"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 06af6e59-c7aa-4c8d-ac14-b8023a2089f8
  modified: 2026-11-03T19:29:30.781Z
---

"The most important thing of all - every part, every detail has to make logical sense in mechanical sense. Thats the biggest telltale - random parts, random bolts, random wedges that are useless" (Michael, 2026-11-03).

**Why:** decorative greebles with no job are what make generated models read as programmer art, more than polycount or texturing.

**How to apply:**
- Before adding any part, say what it does (fastens, braces, feeds, cools, pivots, signals). If there's no answer, don't add it.
- Bolts must fasten something. Gussets must carry a load. Hinges need a door. Glow only where something is hot or a light.
- Moving parts need a real pivot: e.g. a turret is a yaw fork plus a pitching cradle on trunnions, not a head welded to a neck.
- Fluid and fuel lines go from a source to a consumer.
- Keep art_src/FUNCTION.md (part -> job) up to date in the stellar-td repo, and audit with art_src/inspect.py close-ups.

Follow-ups the same day:
- "every element should be logically mounted together - bolts, welds on the edges and stuff."
- About the skid corner block: "its just a cube that has its own shape and its just inserted here with no context... Fix stuff like this".

So, beyond needing a job, every part must be visibly fastened (bolts on flanges, welds in inside corners, fittings, clamps, base plates). Its size and position must also come from the structure it joins. The kit helpers and the joint table are in art_src/FUNCTION.md. Never set a primitive onto or into another part without a joint.

Later on 2026-11-03, on a close-up of an output port: "Its those details and things that overlap eachother etc that give it away. How can we make a workflow that ensures we do models the right way?" He asked for a blockout stage where every block has a job, a checklist for every connection, and no armour plates without a purpose. Then: "note everything you do down to detail so next time skill is perfect". Then, on a pipe support ring floating off the glass: "pipes half done though".

**What exists now:** `art_src/audit.py` fails the build. Every part needs `kit.part(prefix, job, on, joint)`; floating, overlapping, unfastened, buried and hidden parts are errors. There's also a `--blockout` stage. The skill `~/.claude/skills/blender-game-models` (SKILL.md + LESSONS.md) holds every rule and fix. Add to LESSONS.md in the same turn whenever something new is learned.

**Still check by eye:** rings or bands around things must touch all round (the audit only measures against the declared mount). A model that passes the audit on the first run is suspicious.

Related: [[stellar-td-buildings-grey]].
