## Brainstorming

The pipeline is built to turn a clear plan into verified code. But most ideas don't start clear — they start as a half-formed thought, a vague itch, a "wouldn't it be nice if…". **Brainstorming** is the front door for those: a guided conversation that funnels a fuzzy idea into a focused plan the pipeline can actually run.

Run it with `/rnd-framework:rnd-brainstorm`. It writes no code and spawns no agents — it's just you and a structured back-and-forth that ends in a written plan.

### Why it's worth a separate step

Two problems sink an idea before a single line is written, and brainstorming is aimed squarely at both.

**Starting to build before you know what you're building.** It's tempting to jump straight to `/rnd-framework:rnd-start` with a one-line description and let the planner sort it out. But a plan is only as good as the intent behind it. If the scope, the priorities, and the trade-offs are still vague in your own head, the plan inherits that vagueness — and you find out a day later, in the build, that you were solving the wrong shape of problem. Thinking is the cheapest phase there is. An hour of questions up front saves a wave of wasted building.

**Regression to the mean.** Ask a language model for ideas and it tends to hand back the most common answer — the most popular library, the framing it's seen a hundred times, the approach everyone reaches for first. That answer is sometimes right, but it's never the only option, and it's rarely the *interesting* one. Brainstorming deliberately fights this: it names the obvious default out loud, then forces at least one direction that lies off the well-trodden path — and at least one that questions whether you're even solving the right problem.

The guiding rule is **diverge before you converge**: open the space up wide before narrowing it down, so the plan you land on is one you actually chose, not the first one that showed up.

### How it works

It's a funnel — six phases, each one narrower than the last. The early phases go broad; the later ones close in on a single, scoped plan.

| Phase | What happens |
|---|---|
| **Seed** | Get the raw idea on the table — a feature, a problem, an area to explore. It can be as vague as you like. |
| **Expand** | A handful of broad questions map the space: who benefits, what exists today, why now, what constrains it, what the dream outcome looks like. |
| **Explore** | Two to four *meaningfully different* directions the idea could go — including the obvious default (named honestly) and at least one road-less-traveled angle. You pick the one that resonates, or combine them. |
| **Narrow** | Targeted questions on the chosen direction: minimum viable scope, the two or three things that matter most, what you're willing to sacrifice, the biggest unknown. |
| **Focus** | Everything synthesises into a written plan — problem statement, what's in and out of scope, the approach, priorities, and open questions. |
| **Output** | You choose what happens next: hand the plan straight to `/rnd-framework:rnd-start`, save it for later, refine further, or drop it. |

Every question is a multiple-choice prompt with concrete options drawn from your idea and your codebase — not an open-ended "so, what do you think?". You can always pick an option, override it, or write your own answer. The point of the options is to keep momentum: a whole session is five to eight questions, not twenty.

### What you get out

The result is a **brainstorm plan** — a short, structured document:

- **Problem statement** — what this solves, and for whom
- **Scope** — what's in, and (just as important) what's deliberately deferred
- **Approach** — the high-level strategy, not implementation detail
- **Priorities** — the two or three things that matter most, ranked
- **Open questions** — what's still unresolved

That plan is exactly the kind of input the pipeline runs best on. The smoothest path is brainstorm first, then feed the result into `/rnd-framework:rnd-start` — the framework writes its full pre-registration from a plan that already knows what "done" means, instead of guessing from a one-liner. The two steps are designed to hand off to each other.

### In depth

<details>
<summary>Why options instead of open questions</summary>

Every question in a brainstorm is presented as a small set of concrete choices rather than a blank prompt. This isn't to put words in your mouth — you can always override or write your own. It's about momentum and quality. A blank "what do you want?" invites a blank answer; two or three concrete options drawn from your idea give you something to react to, agree with, or argue against. Reacting is faster and sharper than generating from scratch, and the back-and-forth surfaces the constraints that actually matter much quicker than an open interview would.

</details>

<details>
<summary>Naming the obvious answer on purpose</summary>

In the Explore phase, the framework privately names the *baseline* — the first, most-obvious direction, the one anyone (or any model trained on the popular literature) would suggest by default. It doesn't then present that baseline as the safe choice. Its job is to diverge from it: to show you at least one direction most people wouldn't reach for first, and at least one that reframes the problem entirely — "what if this isn't a feature, it's a documentation gap?". The baseline is only offered if it's genuinely the best fit, and when it is, it's labelled honestly as the conventional move rather than dressed up as insight. The goal is for the direction you choose to be one you actually weighed against alternatives.

</details>
