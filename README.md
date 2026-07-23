# dotfiles

Cross-platform dotfiles managed by [dotter](https://github.com/SuperCuber/dotter).

## Configuration patterns

This repo uses a small set of patterns to keep shared configuration reproducible without losing machine-specific or tool-managed local state.

- **Global placeholders, local concrete values**
  Shared templates define defaults or placeholders in tracked files, while each machine can provide its own concrete values through local overrides. This keeps the repository portable across environments without hardcoding local details into tracked files.

- **Two paths for credentials and secrets**
  Private values that differ by machine can live in local overrides, while reusable secrets can be injected at deploy time from Bitwarden via `rbw`. This keeps secrets out of the repo while still allowing templates to render complete working configs.

- **Reverse sync for runtime-managed state**
  Some tools update their own config at runtime, even for values users think of as "preferences" rather than hand-maintained config. Before rendering templates, this repo can sync selected live values back into local variables so a deploy does not immediately overwrite them.

### Why this matters

This pattern helps with a class of problems that many dotfile setups do not handle well: config that is both declarative and locally mutable.

In practice, this means:

- machine-specific values stay local
- secrets stay out of version control
- deploys remain reproducible
- tool-managed state is less likely to be accidentally reset

A concrete example is trusted-project state in coding tools such as Codex. That state is often changed by the tool itself during normal use, not by manually editing config files. Without reverse sync, a later deploy can erase those local trust decisions and force the user to re-approve them.

For implementation details, see:
- [Agent config paths](./AGENTS.md#agent-config-paths-xdg)
- [Variable contract](./AGENTS.md#variable-contract)
- [Template patterns](./AGENTS.md#template-patterns)
- [Live config reverse sync pattern](./AGENTS.md#live-config-reverse-sync-pattern)
