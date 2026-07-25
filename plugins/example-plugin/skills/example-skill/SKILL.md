---
name: example-skill
description: Use as a reference for how a plugin skill is structured, or when demonstrating the example-plugin. A minimal, self-contained placeholder skill.
---

# Example Skill

This is a minimal skill included with `example-plugin` to demonstrate the structure
of a plugin skill. Replace this content with real instructions when you build your
own plugin.

## What a skill is

A skill is a folder containing a `SKILL.md` file with YAML frontmatter (`name` and
`description`) followed by Markdown instructions. Claude loads the skill when the
`description` matches what the user is doing.

## Using this as a template

1. Copy the whole `plugins/example-plugin/` directory to `plugins/<your-plugin>/`.
2. Rename this skill's folder and update the `name` and `description` above.
3. Write the actual instructions Claude should follow here.
