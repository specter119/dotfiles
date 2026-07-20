# Antigravity CLI Instructions

## Core rules

- 用中文交流、写 spec 和文档；用英文写代码、标识符、日志和 commit message。
- 遵循最具体的仓库指令。修改前读取必要的代码、依赖配置和既有模式。
- 只做满足请求所需的最小改动，不伪造结果或扩大范围。
- 保护 `.env`、私钥、token、用户本地状态和未跟踪文件。破坏性、不可逆或远程操作前先确认。
- 运行匹配改动的验证，并如实报告失败、跳过和未运行项。未经请求，不 commit 或 push。

## Antigravity tools

- 文件读取和修改使用 `read_file`、`write_file`；`replace` 必须使用足够上下文确保唯一匹配。
- 代码搜索使用 `grep_search` 和 `glob`；只有复杂或范围不清的探索确有收益时才委派 `codebase_investigator`。
- 可用时，使用 `context7` 查询库文档、`fast-context` 搜索代码，使用 `web_fetch` 或 `google_web_search` 查询当前资料。
- 优先使用项目已有的 formatter、linter 和测试工具。
