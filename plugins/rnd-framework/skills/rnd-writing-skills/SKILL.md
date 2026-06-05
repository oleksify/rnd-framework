---
name: rnd-writing-skills
description: Use when creating new skills for the rnd-framework plugin — skill file format, frontmatter conventions, and best practices
effort: low
---

# Writing Skills

## Overview

Extend the rnd-framework plugin by creating new skills. Skills are Markdown files with YAML frontmatter that guide agent behavior.

## Skill File Format

Every skill lives in its own directory under `skills/`:

```
skills/
  my-new-skill/
    SKILL.md
```

### Required Frontmatter

```yaml
---
name: my-new-skill
description: Use when [triggering conditions] — [what it does]
---
```

- **name:** Lowercase, hyphenated. Must match the directory name.
- **description:** Starts with "Use when" — describes WHEN to invoke this skill, not what it contains. This is what the agent sees when deciding whether to invoke. Do not quote the value unless it contains YAML-special characters (`:`, `#`, `{`, `}`, etc.).

### Body Structure

```markdown
# Skill Name

## Overview
One-sentence core principle.

## When to Use
- Trigger conditions
- When NOT to use

## The Iron Law / Core Principle
The non-negotiable rule.

## Process
Step-by-step guidance.

## Common Rationalizations
Anti-patterns to avoid.

## Verification Checklist
How to confirm the skill was followed correctly.

## Related Skills
Cross-references to other rnd-framework skills.
```

## Naming Conventions

- Use `rnd-` prefix for skills that are part of the R&D pipeline
- Use descriptive names without prefix for utility skills
- Reference other skills as `rnd-framework:<skill-name>`

## Skill Types

**Rigid:** Follow exactly. The skill contains discipline that should not be adapted away. Examples: `rnd-building`, `rnd-verification`.

**Flexible:** Adapt principles to context. The skill provides guidelines, not strict rules. Examples: `rnd-scaling`, `rnd-completion`.

State which type your skill is in the body.

## Testing Your Skill

1. Verify frontmatter parses correctly: `head -5 skills/my-skill/SKILL.md`
2. Verify session-start hook still works: `bash hooks/session-start | python3 -m json.tool`
3. Test invocation: use the Skill tool to invoke your skill and verify it loads

## Related Skills

- `rnd-framework:rnd-using-rnd-framework` — Bootstrap skill that lists all available skills
