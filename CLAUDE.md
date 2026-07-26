# claude-code-plugins

A Claude Code plugin marketplace. Each plugin lives in `plugins/<name>/` and is
registered in `.claude-plugin/marketplace.json`.

## Conventions

- **All plugin names must start with the `dcc-` prefix.** This applies to the
  `name` field in `plugins/<name>/.claude-plugin/plugin.json`, the matching
  entry in `.claude-plugin/marketplace.json`, and the plugin's directory name —
  all three must agree.
- Plugin names are lowercase kebab-case after the prefix, e.g. `dcc-telegram-notify`.

## Validation

Run before committing any manifest change:

```
claude plugin validate .
```

CI runs the same command on every push to `main` and every pull request.
