# Private LLM context

Agent memories, harness notes, and project context are shared through a
separate **private** Git repository. The public dotfiles repository contains
only templates and the tooling needed to work with that checkout.

## Paths and layout

The defaults are:

```text
~/.local/share/llm-context/   # private Git checkout (optional)
~/.codex/memories/             # local seed; never copied automatically
```

The private repository should use this layout:

```text
shared/
  CONTEXT.md                    # durable, sanitized working agreements
  MEMORY.md                     # selected cross-project memories
projects/<project>/             # sanitized project context and handoffs
tools/
  codex/AGENTS.md
  claude/CLAUDE.md
  gemini/GEMINI.md
  jules/AGENTS.md
  cursor/hooks.json
  command-code/context.md
  opencode/AGENTS.md
```

Only deliberately selected, sanitized Markdown and configuration belong in
this repository. Do not copy the whole `~/.codex/memories` tree: rollout
transcripts, local state databases, and host-specific paths can contain
secrets or irrelevant history. Start by reviewing the seed files and copying
only the durable context that is safe to share privately.

The Home Manager module installs the public templates at
`~/.config/llm-context/templates` and the `llm-context-sync` command. It does
not require that the private checkout exists, and it does not overwrite an
existing client configuration. When a private checkout is ready, link a
tool's file explicitly after reviewing it, for example:

```sh
target="$HOME/.codex/AGENTS.md"
if [ -e "$target" ] || [ -L "$target" ]; then
  printf 'Refusing to replace existing %s\n' "$target" >&2
else
  mkdir -p "$(dirname "$target")"
  ln -s "$LLM_CONTEXT_DIR/tools/codex/AGENTS.md" "$target"
fi
```

Use the equivalent target for each tool only when that tool's configuration
format and loading behavior have been verified. A missing private file is
never replaced with a template automatically.

## Explicit synchronization

`llm-context-sync` performs one requested Git operation at a time. It never
runs from a shell startup file or an agent CLI hook.

```sh
llm-context-sync status
llm-context-sync pull       # fast-forward only
llm-context-sync rebase     # fetch and rebase onto the configured upstream
llm-context-sync push
```

Set `LLM_CONTEXT_DIR` to use another checkout and
`LLM_CONTEXT_SEED` to point at another seed directory. `status` is safe when
the checkout has not been cloned yet; network operations fail with an
actionable message instead of creating a repository implicitly.

## Data that must stay out

Never commit API keys, OAuth files, credential stores, session transcripts,
histories, caches, SQLite state, plugin databases, or private SSH material.
The public repository has ignore rules and `scripts/check-llm-context-safe.sh`
has a path/content check for common accidental leaks. This check is a guard,
not a substitute for reviewing a private-repository diff before pushing.

The existing `agy` completion is intentionally left to the zsh migration
slice; document or link it only after its source is confirmed.
