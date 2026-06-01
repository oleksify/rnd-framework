## Introduction

> ⚠️ **Before you rely on this.** This is a highly experimental personal project, built and dogfooded for one workflow. No support, no stability promise, and it may not behave the way you expect.
>
> - **It burns a lot of tokens.** Every task fans out across multiple agents — planning, building, verifying, cleanup, integration — each in its own context window. A single run can cost many times what one Claude session would. This is the point of the design, not a bug, but budget accordingly.
> - **It's slow.** Sequential agent spawns and independent verification add real wall-clock time. It trades speed for rigor.
> - **It's opinionated.** The pipeline imposes pre-registration, information barriers, and quality gates whether or not your task needs them. Small tasks get heavy ceremony.
> - **It changes without notice.** Versioned 0.x on purpose — interfaces, protocols, and quality gates shift between releases, and things break.
>
> If you want a fast, cheap, lightweight assistant, this isn't it. If you want maximum verification rigor and don't mind paying for it, read on.

**rnd-framework** is a plugin for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). It turns "ask the model to write some code" into a structured pipeline: split the task into pieces, write down what success looks like up front, build it, then have a separate reviewer check it without seeing how it was built, and only then combine the results.

The design borrows a few habits from how science and systems engineering keep work honest — writing down what you'll check before you start, having someone other than the author check the result, and asking for evidence at each checkpoint rather than taking "looks good" on faith. Those ideas are explained in [Concepts](#concepts).

### Install

```
/plugin marketplace add https://tangled.org/oleksify.me/rnd-framework.git
/plugin install rnd-framework@oleksify-plugins
```

Update with `/plugin update rnd-framework@oleksify-plugins`.

Then start a pipeline with `/rnd-framework:rnd-start <task>` — see [Getting started](#getting-started).
