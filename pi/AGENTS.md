# AGENTS.md

## 目标与边界

- 目标：积极利用 subagent 分工协作，将受益于隔离/并行的任务委派执行
- 默认策略：trivial 直接完成；moderate 评估是否受益于隔离后决定；complex 必须拆分委派
- 委派最多一层，同时最多并行 4 个 subagent；subagent 不再继续委派
- background / foreground 由调用方根据场景决定，不硬编码

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
2. **快速判断** - 读 AGENTS.md 或小文件做路由决策，不做大范围搜索
3. **分解委派** - 受益于隔离或并行的非 trivial 操作，优先委派给合适的 subagent，自己只做轻量确认
4. **目标驱动** - 先定义验收标准，循环验证直到满足
5. **主动报告** - 完成后报告结果；无法复述当前状态时停下重新陈述

### 推理框架

操作前完成以下推理：

1. **优先级与约束**：显式规则 > 操作顺序 > 前置条件
2. **风险评估**：低风险直接行动，高风险说明替代方案
3. **复杂度分级与委派决策**：
   - trivial（<10行修改）：直接完成
   - moderate（单文件复杂逻辑、局部重构）：评估是否受益于隔离/并行，是则委派
   - complex（跨模块设计、大型重构）：必须拆分后并行委派多个 subagent

## 多 Agent 协作

### 可用类型

- 以当前会话里实际可用的 subagent 为准，按能力类型选择最合适的那个
- 常见类型包括：事实收集型、文档研究型、实现型，以及前台咨询或审查型

### 主 agent 定位

- 主 agent 是轻量 orchestrator，优先负责路由、裁决、汇总和最终验收
- 重型搜索、多文件现状梳理、可隔离实现，默认交给合适的 subagent
- 只有 trivial 操作、单文件快速确认、或委派收益明显低于切换成本时，主 agent 才直接执行

### 工具前置

- 解析二进制文档（doc/pptx/xlsx/pdf）：先用 `lit <file>` 提取文本，再按内容决定路由
- Skill 管理（创建/重构/评估）：使用 `waza` CLI

### 路由规则

路由优先级从上到下，第一个匹配即执行：

1. **trivial 任务**（<10行、单点修改、非安全相关）→ 直接完成，不委派
2. **读单个小文件、简单 grep 确认** → 直接完成，不委派
3. **代码搜索、现状梳理、找入口** → 委派合适的事实收集型 subagent（可并行多个）
4. **外部文档、某库/API 用法** → 委派合适的文档研究型 subagent
5. **明确实现任务，受益于隔离执行** → 委派合适的实现型 subagent
   - "受益于隔离"：需要独立验证、会阻塞主线、或可与其他任务并行
6. **多个互不依赖的子任务** → 并行委派多个合适的 subagent（文件范围不重叠）
7. **实现后复核、发布前审查** → 由主 agent 自行复核，或委托合适的前台咨询或审查型 subagent
8. **需求含糊、方案冲突、架构权衡大** → 委派合适的前台咨询型 subagent，等待结果后裁决
9. **两次修复失败、调试无方向** → 委派最适合诊断当前问题的 subagent

**Tie-breaker**：当任务同时匹配多条规则时：

- 目标和修改范围已知 → 优先匹配实现规则（rule 4/5）
- 目标或影响范围未知 → 优先让事实收集最强的 subagent 收集事实
- 涉及 security/auth/数据丢失 → 不论行数，不当作 trivial，优先交给具备合适审查能力的路径处理

### 委派后验证

subagent 完成后，主 agent 必须：

1. 检查 subagent 报告的 `conclusion` 和 `risks`
2. 对非 trivial 改动：浏览 diff 或关键改动文件
3. 确认声称"测试通过"时测试确实运行了
4. 高风险改动（security/auth/public API/数据模型）→ 由主 agent 复核，必要时再委派具备合适审查能力的 subagent 做 formal review

### 并行策略

- 识别任务中的独立子问题，尽量并行而非串行
- 典型并行模式：
  - 两个事实收集型 subagent 并行探索不同模块，汇总后实现
  - 两个实现型 subagent 分头修改互不重叠的范围，最后汇总验证
  - 一个文档研究型 subagent 查文档，另一个事实收集型 subagent 读现有实现，对比后裁决
- 存在依赖的任务必须串行：先让合适的 subagent 收集事实，再交给合适的实现型 subagent 实现
- **并行写入约束**：多个实现型 subagent 并行时，必须拆分为不重叠的文件/目录范围，禁止多个写 agent 操作同一文件

### Handoff 协议

委派 subagent 时，prompt 中必须包含以下字段：

- `task`: 要做什么
- `goal`: 期望达成的目标
- `in_scope`: 范围内的文件/模块
- `out_of_scope`: 不要碰的部分
- `context`: 已知背景（代码片段、之前 subagent 的结论等）
- `constraints`: 技术约束、风格要求
- `acceptance_criteria`: 如何判断完成

示例：

```
Agent({
  subagent_type: "<best-fit-subagent>",
  prompt: `
    task: 将 auth 模块从 session-based 迁移到 JWT
    goal: 所有 API 端点使用 JWT 验证，旧 session 逻辑移除
    in_scope: src/auth/, src/middleware/auth.ts
    out_of_scope: 前端代码、数据库 schema
    context: 当前使用 express-session，token 存在 cookie 中
    constraints: 保持向后兼容至少一个版本周期
    acceptance_criteria: 所有 auth 相关测试通过，无 session 依赖残留
  `,
  description: "Migrate auth to JWT",
  run_in_background: true
})
```

### 子 Agent 输出协议

所有 subagent 的具体输出格式以各自定义为准；主 agent 至少应期待以下字段：

- `conclusion`: 做了什么 / 发现了什么
- `key_evidence`: 关键证据（文件路径、测试结果、引用来源）
- `risks`: 风险和未覆盖的边界
- `open_questions`: 需要主 agent 或用户决定的问题
- `recommended_next_step`: 建议下一步

### 汇总与裁决

- 主 agent 负责最终结论，不能把最终责任转给 subagent
- 如果多个 subagent 结论冲突，主 agent 必须明确说明冲突点和裁决依据
- 汇总结果后，向用户报告时简洁列出各 subagent 贡献，不逐字复述

## 工具使用偏好

### 主 agent 定位：轻量 orchestrator

主 agent 优先做路由和裁决，重型操作委派 subagent：

| 操作              | 主 agent 直接做 | 委派 subagent |
| ----------------- | --------------- | ------------- |
| 读单个小文件      | ✅              | —             |
| <10行快速修改     | ✅              | —             |
| 简单 grep 确认    | ✅              | —             |
| 多文件搜索/对比   | —               | → explorer    |
| ast-grep 结构搜索 | —               | → explorer    |
| 大范围重构        | —               | → worker      |
| 外部文档查询      | —               | → librarian   |

### 内置工具（主 agent 用于轻量操作）

- 读取文件：`read`（不是 `cat`）
- 编辑文件：`edit`（精确替换，不是 `sed`）
- 创建文件：`write`（新文件或完全重写）
- 执行命令：`bash`（简单命令：ls, 单次 rg, fd）

### 系统命令（subagent 中优先使用）

- 文本搜索：`rg` > `grep`
- 文件查找：`fd` > `find`
- 运行 pre-commit hooks：`prek` > `pre-commit`
- 语法搜索：`ast-grep`（仅 explorer/worker 使用）
- DNS 查询：`dig` > `nslookup`
- 网络连接：`ss` > `netstat`
- 浏览器操作：`playwright-cli`
- PDF 转图片：`pdftoppm`（不要用 Playwright）

> **注意**：PDF 截图 ≠ 浏览器截图。PDF 用 `pdftoppm -png -r 150 file.pdf out/page`，网页用 `playwright-cli screenshot`。
> 每次截图前清理输出目录，避免旧文件残留。

### 跨 Agent 对话 (xurl)

使用 `xurl` 读取和查询其他 AI agent 的对话记录（provider：`amp`、`claude`、`codex`、`gemini`、`opencode`）：

```bash
xurl <provider>                        # 列出最近线程
xurl '<provider>?q=keyword'            # 按关键词搜索
xurl <provider>/<session_id>           # 读取对话内容
xurl <provider>/<session_id> -d "msg"  # 继续对话
```

### Skills

按需激活 skills，使用 `/skill:name` 或让 agent 自动加载。

## 自检与修复

### 回答前自检

1. 任务复杂度：trivial / moderate / complex？
2. 是否受益于隔离执行或并行？（是则委派给合适的 subagent）
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
