# Darkraise Claude Code Plugins

A [Claude Code](https://code.claude.com) plugin marketplace hosting Darkraise's plugins.

## Add the marketplace

In Claude Code:

```
/plugin marketplace add darkraise/claude-code-plugins
```

Then browse and install a plugin:

```
/plugin install dcc-statusline@darkraise
```

The marketplace identifier is `darkraise` (the name after `@` when installing). The
GitHub repository is `darkraise/claude-code-plugins`.

## Available plugins

| Plugin | Description |
| ------ | ----------- |
| `dcc-statusline` | A status line with an account-colored frame, semantic per-section colour, and context and rate-limit meters. Built for machines running several Claude accounts side by side. |
| `dcc-superpower-companions` | Extends superpowers with 16 model and effort tiered implementer subagents. Scores every plan task, records the assigned implementer in the plan, and dispatches it with a defined escalation ladder. |
| `telegram-notify` | Telegram push notifications when a session finishes a turn, ends on a question, or needs your attention. Cross-platform, multi-account aware, optional LLM summaries. |

`dcc-statusline` needs one extra step after installing. A plugin's own
`settings.json` supports only the `agent` and `subagentStatusLine` keys, so no
plugin can register the main `statusLine` for you. Run `/dcc-statusline install`
once per machine to write that entry into your own settings.

## Adding a new plugin

1. Create `plugins/<your-plugin>/.claude-plugin/plugin.json`. New plugin names
   take the `dcc-` prefix, and the name must match the directory and the
   marketplace entry:

   ```json
   {
     "name": "dcc-<your-plugin>",
     "description": "What it does.",
     "version": "0.1.0",
     "keywords": ["..."]
   }
   ```

2. Pick a starting point from an existing plugin if it helps: `dcc-statusline`
   for scripts, hooks and a slash command; `telegram-notify` for hooks and
   configuration; `dcc-superpower-companions` for agents.
3. Add components under the plugin directory. Claude Code auto-discovers the standard
   directories: `commands/` for slash commands, `skills/<name>/SKILL.md` for skills,
   `agents/` for subagents, `hooks/` for hooks, and `.mcp.json` for MCP servers.
4. Register the plugin in `.claude-plugin/marketplace.json` by adding an entry to the
   `plugins` array:

   ```json
   {
     "name": "dcc-<your-plugin>",
     "source": "./plugins/dcc-<your-plugin>",
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
