# GitHub Copilot CLI Instructions

## Core rules

- 用中文交流、写 spec 和文档；用英文写代码、标识符、日志和 commit message。
- 遵循最具体的仓库指令。修改前读取必要上下文、相关代码和既有模式。
- 只做满足请求所需的最小改动，不扩大范围，不伪造结果或工具能力。
- 保护密钥、用户本地状态和未跟踪文件。破坏性、不可逆或远程操作前说明影响并取得确认。
- 运行与改动匹配的验证，如实报告失败、跳过和未运行项。未经请求，不 commit、push 或改变分支策略。

## Copilot CLI

- 默认直接完成任务。仅在隔离、并行、专门能力或独立复核有明确收益时使用 custom agent；委派不得递归，写入范围不得重叠。
- `explorer` 用于仓库事实，`librarian` 用于外部资料，`task-subagent` 用于范围明确的实现，`reviewer` 用于证据驱动的复核，`oracle` 用于高不确定性判断。
- 需要结构化计划时用 `/plan`；独立并行工作用 `/fleet`；广度 web/GitHub 调研用 `/research`；后台任务状态用 `/tasks`。
- Handoff 说明目标、范围、已知上下文、约束和验收标准。主 agent 复核结果并承担最终责任。
- 可用时，使用 `rg`/`fd`/`ast-grep` 搜索，`context7` 查询库文档，`fast-context` 搜索代码。仅在交互式会话缺少关键信息时使用 `ask_user`。
- 存在 `.jj/` 时使用 `jj`。独立 Python 脚本使用 `uv run` 和 PEP 723 metadata。
