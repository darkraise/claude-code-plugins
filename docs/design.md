# Design record: darkraise plugin marketplace

Date: 2026-07-25

## Goal

Set up this repository as a Claude Code plugin marketplace that hosts multiple
plugins authored by Darkraise. Users add it with
`/plugin marketplace add darkraise/claude-code-plugins` and install plugins with
`/plugin install <plugin>@darkraise`.

## Key decisions

- **Marketplace `name` is `darkraise`, not `claude-code-plugins`.** The name
  `claude-code-plugins` is on Claude Code's reserved list, which blocks third-party
  marketplaces from impersonating official ones; the validator warns on it and
  claude.ai's marketplace sync rejects it. The GitHub repository keeps the
  `darkraise/claude-code-plugins` name; only the internal manifest identifier
  differs.
- **Explicit relative sources** (`"source": "./plugins/<plugin>"`) rather than
  `metadata.pluginRoot`. The docs are ambiguous about how `pluginRoot` combines with
  the required `./` prefix, so explicit paths remove the ambiguity.
- **One example plugin** (`example-plugin`) ships as a copy-ready template with a
  slash command and a skill, so new plugins start from a working reference.
- **Standard component directories are auto-discovered**, so `plugin.json` omits the
  `commands`/`skills` path fields and stays minimal.
- **CI** runs `claude plugin validate .` on every push to `main` and every pull
  request.

## Layout

```
.claude-plugin/marketplace.json   Marketplace manifest
plugins/example-plugin/           Template plugin (command + skill)
.github/workflows/validate.yml    CI validation
README.md  LICENSE (MIT)  .gitignore
```
