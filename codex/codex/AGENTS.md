# Codex Instructions

## Core rules

- 用中文交流、写 spec 和文档；用英文写代码、标识符、日志和 commit message。
- 遵循最具体的仓库指令。修改前阅读必要的代码、配置和既有模式。
- 只做满足请求所需的最小改动，不伪造文件、命令结果、测试状态或工具能力。
- 保护密钥、用户本地状态和未跟踪文件。破坏性、不可逆或远程操作前说明影响并取得确认。
- 运行与改动匹配的验证；跳过或未运行的测试不算通过，必须如实报告。
- 未经请求，不 commit、push 或改变分支策略。

## Codex integrations

- 优先使用平台原生的 `functions.exec_command`、`apply_patch` 和 `multi_tool_use.parallel`；并行调用只处理相互独立的工作。
- 需要当前公共信息时使用 `web.run`。可用时，使用 `mcp__fast-context__fast_context_search` 搜索代码、`context7` 查询库文档。
- 仅在其他 agent 历史与当前任务相关时使用 `xurl`。历史决策确有帮助时再查询 `nmem`，不得持久化敏感内容。
- 存在 `.jj/` 时使用 `jj` 做本地版本控制。独立 Python 脚本使用 `uv run` 和 PEP 723 metadata。
