# example-plugin

A minimal template plugin for the `darkraise` marketplace. It exists to show the
structure of a Claude Code plugin and to be copied as the starting point for a new
plugin.

## Contents

| Component | Path | Purpose |
| --------- | ---- | ------- |
| Manifest | `.claude-plugin/plugin.json` | Plugin metadata (name, version, author). |
| Command | `commands/hello.md` | A trivial `/hello` slash command. |
| Skill | `skills/example-skill/SKILL.md` | A minimal reference skill. |

## Try it

After adding the marketplace and installing this plugin, run `/hello` in Claude Code.

## Start a new plugin from this template

1. Copy this directory to `plugins/<your-plugin>/`.
2. Update `.claude-plugin/plugin.json` (`name`, `description`, `version`, `keywords`).
3. Replace or remove the example command and skill, and add your own components.
4. Register the plugin in the repository's `.claude-plugin/marketplace.json`.
5. Run `claude plugin validate .` from the repository root.
