## Concepts

The framework rests on six ideas. Each one borrows a habit from science or engineering and applies it to writing code.

| Idea | In plain terms |
|---|---|
| **Pre-registration** | Write down what "done" means *before* writing the code |
| **Decomposition** | Split the work into small pieces, each with its own check |
| **Independent verification** | A separate reviewer checks the work without seeing the author's reasoning |
| **Evidence-based gates** | Every checkpoint needs proof you can re-run, not a "looks good" |
| **Wave scheduling** | Work out what can run in parallel and what has to wait |
| **Outside view** | Sanity-check the plan against how often this kind of work has failed before |

### Pre-registration

Decide what success looks like — and how you'll check it — before you write a line of code, so the goalposts can't quietly move once the code exists. (Scientists do the same thing: they register an experiment before they run it.)

Here, the planner writes a **validation contract**: one testable statement for each thing the change has to do, locked in up front. The builder can't redefine "done" halfway through, and the reviewer checks against that contract — not against whatever happened to get built.

### Decomposition

A big task is split into a tree of small pieces. Each piece is small enough to keep in your head, has its own definition of done, and is checked on its own. Small pieces fail in obvious ways; big ones fail in ways you don't notice until much later.

### Independent verification

The reviewer is deliberately not the author — and can't see the author's notes. The reason is simple: if the reviewer reads "I think this is fine, that edge case probably won't happen," they tend to believe it, and the review becomes a rubber stamp. Keeping the two apart keeps the review honest. See [Information barrier](#information-barrier) for how that separation is enforced.

### Evidence-based gates

A **gate** is a checkpoint between phases. To get through, a phase has to show proof you can reproduce — a command that exits cleanly, a file that's actually there, a test that runs and passes — not just a claim that it works. "Should be fine" doesn't get through.

### Wave scheduling

Before building, the planner works out which pieces depend on which. The ones that don't depend on each other are grouped into a **wave** and built together; the rest wait for the piece they need. It's the same dependency-ordering a build tool does — just applied to tasks instead of files.

### Outside view

When you size up a task by looking only at the task in front of you, you tend to be optimistic — "this one will go smoothly." A more reliable check is to step back and ask: how often has work *like this* actually gone wrong before?

So right before planning, the framework looks at this project's own track record. It groups past work by kind — the logs call this its **shape** (a database change, a behaviour change, a docs edit, and so on) — and, for each kind, measures how often it failed review. Those failure rates are handed to the planner as a reality check while it builds the plan.

It's a reality check, not an instruction. A low past-failure rate isn't a reason to cut corners; a high one isn't a reason to over-split the task into tiny pieces. It's just useful context. And when the project doesn't have enough history yet — fewer than five past results — the framework says so instead of guessing a number.
