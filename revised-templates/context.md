# Recent Context

<!--
Purpose: Continuity bridge across sessions. Rolling window (~5 days).
This is the "previously on..." that prevents the user from
re-explaining what they're doing every session.

Design principle: Write for your future self at session start.
What would you need to read in 30 seconds to pick up naturally?
Cull aggressively — if it's not active, archive or delete it.
-->

## Right Now
<!-- 3-5 sentence snapshot. What's the current state of things?
Write like you're briefing someone who already knows the project. -->
{{CURRENT_SNAPSHOT}}

## Active Threads

<!-- 1-4 max. Each thread = a coherent line of work.
If a thread is done, move it to Archive or delete it. -->

### {{THREAD_NAME}}
**Status:** {{ACTIVE / BLOCKED / WRAPPING UP}}
**Last touched:** {{DATE}}

What's happening: {{1-3 sentences on current state}}

Recent moves:
- {{ACTION_1}}
- {{ACTION_2}}

Next likely step: {{NEXT_STEP}}

---

## Decisions & Shifts
<!-- Only things that change direction or close off options.
Not "chose tabs over spaces" — more like "switched from REST to GraphQL." -->
- {{DECISION}}: {{ONE_LINE_RATIONALE}}

## Current Energy
<!-- Optional. Surprisingly useful for calibrating interaction style. -->
- Bandwidth: {{LOW / MEDIUM / HIGH}}
- Notes: {{e.g., "deadline Friday" / "exploratory mood" / "burned out, keep it light"}}

## Parked Threads
<!-- Recently active but not current. One line each. Delete after ~1 week. -->
- {{THREAD}} — {{STATUS_NOTE}}

---
Window: {{START_DATE}} to {{END_DATE}}
Updated: {{DATE}}
