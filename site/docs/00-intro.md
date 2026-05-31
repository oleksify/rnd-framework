## Introduction

**rnd-framework** is a plugin for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). It turns "ask the model to write some code" into a structured pipeline: decompose the task, declare what success looks like up front, build it, then verify it independently behind an information barrier, and only then integrate.

The design borrows a few ideas from how science and systems engineering keep work honest — declaring a hypothesis before running the experiment, having someone other than the author check the result, and requiring evidence rather than assertions at each checkpoint. Those ideas are explained in [Concepts](#concepts).

> **Before you rely on this.** It is a highly experimental personal project, built and dogfooded for one workflow. It burns a lot of tokens — every task fans out across multiple agents, each in its own context window, so a single run can cost many times what one Claude session would. It is slower than working directly, by design. It is opinionated: small tasks still get the full ceremony. And it is versioned `0.x` on purpose — interfaces and quality gates change between releases. If you want a fast, cheap assistant, this is not it.

### Install

```
/plugin marketplace add https://tangled.org/oleksify.me/rnd-framework.git
/plugin install rnd-framework@oleksify-plugins
```

Update with `/plugin update rnd-framework@oleksify-plugins`.

Then start a pipeline with `/rnd-framework:rnd-start <task>` — see [Getting started](#getting-started).
