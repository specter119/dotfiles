# Copilot Hooks

当前暂不启用 `rtk-rewrite.json.bak`，原因是 Copilot CLI / VS Code Copilot Chat 的 hook 行为仍有上游兼容问题。

## 当前状态

- `rtk-rewrite.json.bak`：保留配置内容，但通过 `.bak` 后缀避免 Copilot CLI 加载。
- 等相关 issue 修复并验证后，再改回 `rtk-rewrite.json`。

## 相关 issue

- https://github.com/github/copilot-cli/issues/2585
  - `preToolUse` hook 返回的 `additionalContext` 没有传递给 agent。
- https://github.com/github/copilot-cli/issues/2643
  - `updatedInput` + `permissionDecision: allow` 仍会弹确认，无法静默 rewrite 命令。
- https://github.com/rtk-ai/rtk/issues/1425
  - VS Code Copilot Chat 的 `run_in_terminal` 输入格式未被 `rtk hook copilot` 正确识别。

## 恢复方式

确认上游问题修复后：

```bash
mv copilot/hooks/rtk-rewrite.json.bak copilot/hooks/rtk-rewrite.json
```
