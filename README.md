# Darkraise Claude Code Plugins

A [Claude Code](https://code.claude.com) plugin marketplace hosting Darkraise's plugins.

## Add the marketplace

In Claude Code:

```
/plugin marketplace add darkraise/claude-code-plugins
```

Then browse and install a plugin:

```
/plugin install example-plugin@darkraise
```

The marketplace identifier is `darkraise` (the name after `@` when installing). The
GitHub repository is `darkraise/claude-code-plugins`.

## Available plugins

| Plugin | Description |
| ------ | ----------- |
| `telegram-notify` | Telegram push notifications when a session finishes a turn, ends on a question, or needs your attention. Cross-platform, multi-account aware, optional LLM summaries. |
| `dcc-superpower-companions` | Extends superpowers with 16 model and effort tiered implementer subagents. Scores every plan task, records the assigned implementer in the plan, and dispatches it with a defined escalation ladder. |
| `example-plugin` | A minimal template plugin demonstrating a slash command and a skill. Clone it to start a new plugin. |

## Adding a new plugin

1. Copy `plugins/example-plugin/` to `plugins/<your-plugin>/`.
2. Edit `plugins/<your-plugin>/.claude-plugin/plugin.json`: set `name`, `description`, `version`, and `keywords`.
3. Add components under the plugin directory. Claude Code auto-discovers the standard
   directories: `commands/` for slash commands, `skills/<name>/SKILL.md` for skills,
   `agents/` for subagents, `hooks/` for hooks, and `.mcp.json` for MCP servers.
4. Register the plugin in `.claude-plugin/marketplace.json` by adding an entry to the
   `plugins` array:

   ```json
   {
     "name": "<your-plugin>",
     "source": "./plugins/<your-plugin>",
     "description": "What it does.",
     "keywords": ["..."]
   }
   ```

5. Validate before committing:

   ```
   claude plugin validate .
   ```

## Repository layout

```
.claude-plugin/marketplace.json   Marketplace manifest (lists every plugin)
plugins/<plugin>/                 One directory per plugin
  .claude-plugin/plugin.json      Plugin manifest
  commands/  skills/  agents/     Plugin components (auto-discovered)
.github/workflows/validate.yml    CI: runs `claude plugin validate .`
```

## Validation

Every push to `main` and every pull request runs `claude plugin validate .` via
GitHub Actions (see `.github/workflows/validate.yml`) to catch manifest errors
before release.

## License

[MIT](LICENSE) &copy; 2026 Darkraise
