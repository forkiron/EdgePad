---
description: Implement a feature from its spec file
argument-hint: <spec-number-or-name>
allowed-tools: Read, Write, Edit, Grep, Glob, Bash(swift *), Bash(./build.sh *)
---

# Implement feature spec: $ARGUMENTS

Follow the EdgePad development workflow:

1. **Read** `docs/specs/$ARGUMENTS.md` (or the closest match if fuzzy)
2. **Read** `docs/PRD.md` and `docs/ARCHITECTURE.md` for context
3. **Read** existing Sources to understand patterns
4. **Think hard** about the cleanest implementation that fits the existing style
5. **Implement** the feature incrementally:
   - Add/modify data models first
   - Add/modify the controller / logic component
   - Wire it up in `AppDelegate`
   - Update `OverlayWindow` HUD if needed
6. **Build** with `./build.sh` and fix any errors
7. **Update** the spec's acceptance criteria checkboxes as you complete them
8. **Report** what changed, what's tested, and what's left

Do not invent features not in the spec. If the spec is ambiguous, ask before guessing.
