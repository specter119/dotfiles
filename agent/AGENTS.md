# Agent Package Contracts

Authoring guidance for the agent-layer packages (`agent`, `droid`, `pi`, and peers under the `agent` composition).

This file is **not** a live runtime prompt for end-user repos. It is maintenance guidance for this dotfiles tree. Tool-specific runtime policy stays in each tool's own `AGENTS.md` (e.g. `droid/config/AGENTS.md`, `pi/AGENTS.md`).

Repo-wide package/template/variable rules remain in the root [`AGENTS.md`](../AGENTS.md). Dotter deploy internals remain in [`.dotter/AGENTS.md`](../.dotter/AGENTS.md).

## Skill and Subagent Routing Contract

Cross-tool rule for placing "what this is" vs "when the caller must do it". Applies when editing skill descriptions, subagent/droid descriptions, and per-agent `AGENTS.md` delegation or gate rules.

### Pull vs push

| Surface | Role | Trigger style |
| --- | --- | --- |
| Skill `description` ("what" + "Use when…") | Capability ad + situation match | **pull** |
| Subagent / droid `description` ("what I am" + "when to pick me") | Capability ad + situation match | **pull** |
| Caller `AGENTS.md` ("at gate G you must do X") | Control-flow obligation | **push** |

Skill "Use when…" and subagent "when to pick me" are the **same category**: situation → tool matching. They are not the same as an AGENTS.md obligation. The real axis is **pull capability hint** vs **push control-flow duty**, not "what vs when".

### Runtime placement (why it matters)

- **Skills**: name + description are injected into the main agent context as a resident catalog, often with an "actively consider using" nudge. Still pull: the model must recognize the situation.
- **Subagent / droid descriptions**: live in the delegation tool catalog / schema (e.g. Droid `Task` `subagent_type`, Pi `pi-subagents` agent list). Best case they help **which** agent to pick after the caller already decided to delegate. The subagent body is only read **after** dispatch, so it cannot trigger its own invocation.
- **Caller AGENTS.md**: unconditional resident project/tool policy. Correct home for imperative "must" gates.

Models under-delegate by default. Vague "use as needed" language is not a quality gate.

### Placement rules

1. **Capability / routing** ("I am X; pick me for Y") → skill or subagent/droid `description` (pull).
2. **Obligation / gate** ("before ExitSpecMode / before finalizing an irreversible plan, you must review") → caller `AGENTS.md` (push).
3. Do **not** put a mandatory gate only in a subagent description or body. Description cannot force the caller; body is unread until after call.
4. Avoid duplicating the same "when" list in both places. Split roles: description = select-which; AGENTS.md = must-when.
5. Prefer a concrete chokepoint when the tool has one (Droid: `ExitSpecMode`). If there is no gate (Pi), write an explicit heuristic push trigger in AGENTS.md instead of relying on description pull.

### Why not a skill

This contract is standing authoring guidance for maintaining agent configs. A skill would itself be pull ("consider this when editing agents"), which is the wrong delivery for a placement rule that should stay next to the agent package layer. Keep the theory here; tool-specific AGENTS.md only carry the local obligation bullets.

### Current applications

- **Droid** `droid/config/AGENTS.md` → `## Spec Mode`: push gate before `ExitSpecMode`; oracle droid description stays pull.
- **Pi** `pi/AGENTS.md` → `## Delegation`: heuristic push trigger for high-uncertainty / irreversible plans; oracle agent description stays pull.
