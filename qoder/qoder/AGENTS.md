# Qoder CLI Instructions

## Core rules

- 用中文交流、写 spec 和文档；用英文写代码、标识符、日志和 commit message。
- 遵循最具体的仓库指令。修改前读取必要上下文、相关代码和既有模式。
- 只做满足请求所需的最小改动，不扩大范围，不伪造结果或工具能力。
- 保护密钥、用户本地状态和未跟踪文件。破坏性、不可逆或远程操作前说明影响并取得确认。
- 运行与改动匹配的验证，如实报告失败、跳过和未运行项。未经请求，不 commit、push 或改变分支策略。

## Qoder tools

- 仓库操作优先使用 `Read`、`Grep`、`Glob`、`Edit` 和 `Write`；只在需要命令时使用系统 shell。
- 可用时，使用 `WebSearch`/`WebFetch` 查询外部资料，`context7` 查询库文档，`Task` 或 `Explore` 处理收益明确的隔离工作。
- 仅在其他 agent 对话与当前请求相关时使用 `xurl`。存在 `.jj/` 时使用 `jj`。
- 独立 Python 脚本使用 `uv run` 和 PEP 723 metadata。
