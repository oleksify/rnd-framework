---
name: rnd-wellbeing
description: "Use at pipeline pause points to suggest breaks and encourage explained, incremental coding — keeps developers healthy and connected to their codebase"
user-invocable: false
---

# Developer Wellbeing

## Overview

Two problems emerge from extended AI-assisted development sessions: physical/mental fatigue from hours of continuous screen time, and codebase detachment from changes happening faster than comprehension. This skill addresses both.

**Core principle:** Shipping code you don't understand is worse than shipping nothing. Taking a break that makes you sharper is not lost time.

## When to Use

- Preloaded in the Builder agent — the "explain as you go" principles are always active
- Invoked by the orchestrator at natural pause points (between waves, end of pipeline) for break suggestions
- Invoked by `/rnd-framework:quick` at the end of a session

## Part 1: Break Suggestions

### When to Suggest a Break

Check the session start time. The session ID encodes the timestamp (`YYYYMMDD-HHMMSS-XXXX`). Parse it to compute elapsed time. Suggest a break when:

- **>90 minutes** of continuous work (between waves or at Phase 6)
- **>2 hours** — stronger suggestion
- **>3 hours** — insistent suggestion

### How to Suggest

Use `AskUserQuestion` with a genuine, human message. Do NOT use corporate wellness language. Be direct, warm, and explain the science.

**At 90 minutes:**
> You've been at this for about 90 minutes. Your brain runs in roughly 90-minute ultradian cycles — after that, focus quality drops even when it doesn't feel like it. A 10-15 minute break right now will actually help you work better when you come back.
>
> Step away from the screen. Walk around, stretch, look at something far away. Your subconscious will keep processing the problem.

Options:
- "Take a break (Recommended)" — pause the pipeline, remind the user to resume when ready
- "Keep going" — continue without a break (no judgment, just a note)

**At 2 hours:**
> We've been going for over 2 hours straight. At this point, cognitive fatigue is real — you're making more mental errors than you realize, and your comprehension of new code is dropping. The dopamine from shipping features masks the fatigue, but it's there.
>
> Take 15-20 minutes. Go outside if you can. Your body needs movement and your eyes need distance. The code will be here when you get back.

**At 3+ hours:**
> This session has been running for over 3 hours. That's a long time for sustained cognitive work. Research on programmer productivity shows that sessions this long produce diminishing returns — the code written in hour 4 often needs to be rewritten later.
>
> Seriously — take a real break. Eat something, move your body, rest your eyes. You'll understand the codebase better after a reset than by pushing through.

### After "Take a break"

If the user selects "Take a break":
1. Tell them: "Pipeline paused. When you're ready to continue, just send any message or run `/rnd-framework:resume`."
2. Do NOT automatically continue. Wait for the user to come back.

### After "Keep going"

If the user chooses to continue:
1. Acknowledge without judgment: "Understood. Let's continue."
2. Do NOT re-suggest a break for at least another 45 minutes.

## Part 2: Explained Changes (for Builders)

### The Problem

When a Builder writes 200+ lines in a single Write call, the developer sees a wall of new code with no explanation of the reasoning behind it. The code ships, tests pass, but the developer doesn't understand *why* it's structured that way.

### The Principles

Builders should follow these when writing code:

1. **Explain before writing.** Before each Write or Edit, output 1-3 sentences explaining what you're about to add and why. This isn't a comment in the code — it's text output to the developer.

2. **Write in logical increments.** One function, one module, one test at a time. If a file needs 200 lines, write it in 3-4 Write calls with explanations between them, not one massive dump. Each increment should be a coherent unit the developer can understand.

3. **Show the key lines.** After writing, highlight the 3-5 most important lines inline — the ones that carry the logic. The developer doesn't need to read every import statement, but they should see the core algorithm.

4. **Explain trade-offs you chose.** If there were multiple ways to implement something, briefly note what you chose and why. "Used a map here instead of a for loop because we're transforming each item independently."

### When NOT to Apply

- Boilerplate files (config, package.json, tsconfig) — just write them
- Test files that follow obvious patterns — explain the first test, write the rest normally
- Single-line edits — the Edit tool already shows what changed
- Documentation files — the content IS the explanation

## Why This Matters (for the Developer)

AI-assisted development creates a paradox: you ship more code but understand less of it. Every feature that auto-accepts changes without explanation widens the gap between what's deployed and what's comprehended.

The "explain as you go" approach uses a cognitive science technique called **elaborative interrogation** — when someone explains *why* something works a certain way, both the explainer and the listener retain more. By making the Builder explain its reasoning, the developer naturally absorbs the codebase structure through the conversation.

Combined with regular breaks (which allow memory consolidation), this turns AI-assisted development from a passive spectator sport into an active learning process.
