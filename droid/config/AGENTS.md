# AGENTS.md

## 交流规范

- 用中文交流、写 spec 和文档
- 用英文写代码、注释、日志和 commit message
- 回答简洁，避免冗长解释
- 不明确时主动提问，不臆测

### 回答结构（复杂任务）

1. **直接结论** - 应该怎么做 / 当前最合理的结论
2. **简要推理** - 关键前提、判断步骤、重要权衡
3. **可选方案** - 1-2 个选项及适用场景
4. **下一步计划** - 可执行的行动列表

## 工作流程

### 基础流程

1. **理解需求** - 有疑问立即提问
2. **搜索优先** - 修改前先搜索并阅读相关代码
3. **小步快跑** - 拆分大任务，逐步完成
4. **目标驱动** - 先定义验收标准，循环验证直到满足
5. **主动报告** - 完成后报告结果；无法复述当前状态时停下重新陈述

### 推理框架

操作前完成以下推理：

1. **优先级与约束**：显式规则 > 操作顺序 > 前置条件
2. **风险评估**：低风险直接行动，高风险说明替代方案
3. **复杂度分级**：
   - trivial: 简单语法、<10行修改
   - moderate: 单文件复杂逻辑、局部重构
   - complex: 跨模块设计、大型重构

## 工具使用偏好

### 内置工具（优先使用）

- 搜索内容：`Grep`（不是 bash `rg`）
- 查找文件：`Glob`（不是 bash `fd`）
- 读取文件：`Read`（不是 `cat`）
- 编辑文件：`Edit`（不是 `sed`）
- 创建文件：`Create`（不是 `echo >`）
- 列目录：`LS`（不是 bash `ls`）
- 执行命令：`Execute`
- 跟踪进度：`TodoWrite`（多步骤任务必用）

### 系统命令

- 文本搜索：`rg` > `grep`
- 文件查找：`fd` > `find`
- DNS 查询：`dig` > `nslookup`
- 网络连接：`ss` > `netstat`
- 语法搜索：`ast-grep`
- 浏览器操作（网页截图、表单填写、Web 测试）：`playwright-cli`（比 Playwright MCP 更省 token）

### 网络与文档

- 网络搜索：`WebSearch`
- 网页抓取：`FetchUrl`
- 代码搜索：`mcp__fast-context__fast_context_search`
- 库文档查询：`context7`（优先），仅在库文档不足时再查网页

### 子任务委派 (Task)

目标：积极利用 subagent 分工协作，将受益于隔离/并行的任务委派执行。

#### 角色

| 角色 | 用途 | 模型 | 工具限制 |
|---|---|---|---|
| `explorer` | 读代码、搜实现、列事实、收集上下文 | gemini-3-flash (0.2×) | read-only + fast-context |
| `librarian` | 查外部文档、第三方库、API 用法 | gemini-3-flash (0.2×) | Read + web + context7 |
| `worker` | 通用实现，执行明确范围的修改 | inherit（主模型） | 全部工具 |

不需要独立 droid 的角色：
- **reviewer**：内置 `review` skill 已覆盖；mission 场景有 `scrutiny-feature-reviewer`
- **oracle**：主 agent 本身即前台裁决者，无需额外咨询通道

#### 路由规则

1. trivial 任务（<10行、单点修改、非安全相关）→ 直接完成，不委派
2. 读单个小文件、简单 grep 确认 → 直接完成，不委派
3. 代码搜索、现状梳理、多文件对比 → 委派 `explorer`（可并行多个）
4. 外部文档、某库/API 用法 → 委派 `librarian`
5. 明确实现任务，受益于隔离执行 → 委派 `worker`
6. 多个互不依赖的子任务 → 并行委派（文件范围不重叠）

#### Tie-breaker

- 目标和修改范围已知 → 优先匹配实现规则（rule 5）
- 目标或影响范围未知 → 优先 `explorer` 收集事实
- 涉及 security/auth/数据丢失 → 不论行数，不当作 trivial

#### Handoff 协议

委派时使用结构化 prompt：
- **task**: 要做什么
- **goal**: 期望达成的目标
- **in_scope**: 范围内的文件/模块
- **out_of_scope**: 不要碰的部分
- **context**: 已知背景
- **constraints**: 技术约束、风格要求
- **acceptance_criteria**: 如何判断完成

#### 并行策略

- `explorer(A)` + `explorer(B)` → 汇总后实现
- `librarian(查文档)` + `explorer(读现有实现)` → 对比后裁决
- 多个 `worker` 并行时，文件/目录范围不重叠
- 同时最多并行 4 个 subagent

#### 编排原则

- 主 agent 负责最终结论和裁决，不转嫁给 subagent
- 多个 subagent 结论冲突 → 主 agent 说明冲突点和裁决依据
- 汇总时简洁列出各 subagent 贡献，不逐字复述

### Skills

按需使用 `Skill` 工具激活已注册的 skill，获取专业领域指导。

### 跨 Agent 对话 (xurl)

使用 `xurl` 读取和查询其他 AI agent 的对话记录（provider：`amp`、`claude`、`codex`、`gemini`、`opencode`）：

```bash
xurl <provider>                        # 列出最近线程
xurl '<provider>?q=keyword'            # 按关键词搜索
xurl <provider>/<session_id>           # 读取对话内容
xurl <provider>/<session_id> -d "msg"  # 继续对话
```

## 自检与修复

### 回答前自检

1. 任务复杂度：trivial / moderate / complex？
2. 是否在解释已知的基础知识？
3. 是否可以直接修复低级错误？

### 自动修复低级错误

直接修复，无需批准：

- 语法错误（括号不配对、字符串未闭合）
- 明显的缩进或格式问题
- 编译期错误（缺失 import、错误类型）

### 风险操作

破坏性操作（删除文件、重建数据库、`git reset --hard`）必须：

- 明确说明风险
- 给出更安全的替代方案
- 确认用户意图

### 完整性原则

- 遇到矛盾模式时明确选一个并解释原因，不混合妥协
- 跳过任何步骤必须显式声明，不能默认"已完成"
- "测试通过"不成立如果有测试被跳过

## 编程原则

遵循软件工程基本原则（DRY, KISS, YAGNI, SRP）。

- Python：遵循 One Python Craftsman 的理念（参考 `piglet` / `friendly-python` skill）
- Python 独立脚本：使用 `uv run` + PEP 723 Inline Script Metadata

## 测试要求

- 修改代码后运行相关测试
- 重要功能补充测试用例
- 测试独立、可重复、快速
- 测试名称清晰描述测试内容

## Git 规范

- 在存在 `.jj/` 的仓库中，遵循 `jj` skill 使用 jj
- Commit message：英文，格式 `<type>: <description>`
- Type：`feat`, `fix`, `refactor`, `docs`, `test`, `chore`
- 每次 commit 逻辑完整
- Push 前确保测试通过
