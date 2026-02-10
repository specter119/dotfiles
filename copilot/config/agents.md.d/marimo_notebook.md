# Marimo Notebook 使用原则

本文针对数据科学家使用 marimo 的场景，强调"稳定优先、按需交互"。marimo 的 reactive 特性强大但容易过度使用，导致 notebook 不稳定或行为难以预测。

## 资料来源

- <https://docs.marimo.io/>
- <https://docs.marimo.io/guides/reactivity/>

## 核心理念

### 1) 默认简洁，按需交互

- **默认生成静态分析流程**，除非用户明确要求交互式控件
- 数据分析通常是线性流程，过多交互增加复杂度和不稳定性
- 问自己：用户是"探索参数空间"还是"跑一次看结果"？

### 2) 副作用操作必须 gate

| 操作类型         | 必须使用 run_button | 原因                   |
| ---------------- | ------------------- | ---------------------- |
| API 调用         | ✓                   | 避免意外触发、消耗配额 |
| 文件写入         | ✓                   | 防止数据覆盖           |
| 数据库操作       | ✓                   | 不可逆                 |
| 长时间计算 (>5s) | ✓                   | 用户应有明确意图       |
| 纯展示/过滤      | ✗                   | reactive 天然适合      |

### 3) 控制 reactive 链深度

- 避免超过 3 层的 reactive 依赖
- 深层链条导致一个组件变化触发大量重算
- 如需复杂联动，考虑用 `mo.ui.form()` 收束为单次提交

## 场景决策表

| 场景             | 推荐方式             | 避免               |
| ---------------- | -------------------- | ------------------ |
| 一次性 EDA       | 直接计算显示         | 添加参数选择器     |
| 固定参数分析     | 硬编码参数值         | slider/dropdown    |
| 参数敏感性分析   | slider + 轻量计算    | -                  |
| 批量测试/API调用 | run_button gate      | 自动触发的reactive |
| 交互式仪表板     | 全套 UI + reactive   | -                  |
| 表单提交         | mo.ui.form() 包裹    | 多个独立 reactive  |

## 典型 Good/Bad 示例

### 示例 1：一次性分析 - 避免不必要的交互

**Bad**：为单次分析添加不必要的交互控件

```python
@app.cell
def _():
    threshold = mo.ui.slider(0, 1, value=0.5, label="Threshold")
    threshold
    return

@app.cell
def _():
    result = df.filter(pl.col("score") > threshold.value)
    result
    return
```

**Good**：直接硬编码，清晰明了

```python
@app.cell
def _():
    THRESHOLD = 0.5
    result = df.filter(pl.col("score") > THRESHOLD)
    result
    return
```

### 示例 2：副作用操作 - 必须显式确认

**Bad**：API 调用随 reactive 自动触发

```python
@app.cell
def _():
    query = mo.ui.text(label="Query")
    query
    return

@app.cell
def _():
    # 危险：每次输入变化都会调用 API！
    response = call_api(query.value)
    response
    return
```

**Good**：用 run_button 明确触发

```python
@app.cell
def _():
    query = mo.ui.text(label="Query")
    submit = mo.ui.run_button(label="Submit")
    mo.hstack([query, submit])
    return

@app.cell
def _():
    mo.stop(not submit.value)
    response = call_api(query.value)
    response
    return
```

### 示例 3：批量操作 - gate 整个流程

**Bad**：批量测试自动执行

```python
@app.cell
def _():
    test_cases = load_test_cases()
    # 每次 notebook 打开都会跑全部测试！
    results = [run_test(case) for case in test_cases]
    results
    return
```

**Good**：用 run_button 控制执行时机

```python
@app.cell
def _():
    test_cases = load_test_cases()
    run_tests = mo.ui.run_button(label="Run All Tests")
    mo.vstack([mo.md(f"Loaded {len(test_cases)} test cases"), run_tests])
    return

@app.cell
def _():
    mo.stop(not run_tests.value, mo.md("Click button to run tests"))
    results = [run_test(case) for case in test_cases]
    results
    return
```

### 示例 4：复杂表单 - 收束多个输入

**Bad**：多个独立 reactive 输入，每次变化都触发

```python
@app.cell
def _():
    start_date = mo.ui.date(label="Start")
    end_date = mo.ui.date(label="End")
    category = mo.ui.dropdown(options=["A", "B", "C"], label="Category")
    mo.hstack([start_date, end_date, category])
    return

@app.cell
def _():
    # 任何一个输入变化都会重新查询数据库
    data = query_database(start_date.value, end_date.value, category.value)
    data
    return
```

**Good**：用 form 收束为单次提交

```python
@app.cell
def _():
    filter_form = mo.ui.form(
        mo.hstack([
            mo.ui.date(label="Start"),
            mo.ui.date(label="End"),
            mo.ui.dropdown(options=["A", "B", "C"], label="Category"),
        ]),
        label="Query",
        bordered=True,
    )
    filter_form
    return

@app.cell
def _():
    mo.stop(not filter_form.value)
    start, end, cat = filter_form.value
    data = query_database(start, end, cat)
    data
    return
```

## 速查清单

- [ ] 这个分析需要反复调参吗？不需要则硬编码
- [ ] 这个操作有副作用吗？有则 run_button gate
- [ ] reactive 链超过 3 层了吗？考虑用 form 收束
- [ ] 用户期望"即时反馈"还是"确认后执行"？
- [ ] notebook 打开时会自动执行耗时/危险操作吗？

## 变量作用域规则 (MB002: multiple-definitions)

Marimo 的 reactive execution model 要求**每个变量只能在一个 cell 中定义**（single source of truth）。

### 变量命名与共享策略

| 类型 | 命名 | return | 示例 |
| ---- | ---- | ------ | ---- |
| 长期复用的共享对象 | 无 `_` 前缀 | ✓ 导出 | `llm_client`, `df`, `token_mgr` |
| 仅展示的结果 | 不赋值 | 表达式作为最后一行 | `df.head()`, `mo.ui.table(result)` |
| 中间变量 / 循环变量 | `_` 前缀 | ✗ 不导出 | `_resp`, `_row`, `_i` |

**原则**：

- **HTTP/LLM client、需要持续处理的 DataFrame** → 全局共享，在 imports cell 创建并 return
- **展示用的 table / chart** → 不赋变量，直接作为 cell 最后一行表达式
- **循环中间变量、单次 HTTP response** → `_` 前缀，cell-local

### 示例

```python
# Cell 1: imports + shared clients
@app.cell
def _():
    from openai import AzureOpenAI
    from keycloak import get_token

    llm_client = AzureOpenAI(
        azure_endpoint="https://example.com",
        azure_deployment="gpt-4.1-mini-deploy",
        api_version="",
        azure_ad_token_provider=get_token,
    )
    return llm_client,

# Cell 2: processing → shared DataFrame
@app.cell
def _(llm_client):
    df = process_data(llm_client)
    return df,

# Cell 3: display only → no variable, just expression
@app.cell
def _(df):
    df.head()
    return

# Cell 4: loop with intermediate vars
@app.cell
def _(df, llm_client):
    _results = []
    for _row in df.iter_rows(named=True):
        _resp = llm_client.chat.completions.create(...)
        _results.append(_resp)
    result_df = pl.DataFrame(_results)
    return result_df,
```

### 参考

- <https://docs.marimo.io/guides/understanding_errors/multiple_definitions>
- <https://docs.marimo.io/guides/lint_rules/rules/multiple_definitions>

## 工作目录与模块导入

Marimo 的 `__file__` 指向 notebook 文件本身，但工作目录可能不是 notebook 所在目录（取决于启动方式）。为了对齐 Jupyter 的行为并方便导入同目录模块，可以在初始化 cell 中设置工作目录：

```python
@app.cell
def _():
    import os
    from pathlib import Path

    os.chdir(Path(__file__).parent)
    return
```

**注意**：这是一个全局副作用，但作为初始化 cell 的一次性设置是可接受的。

## 自动渲染的数据类型

Marimo 会自动渲染以下类型，直接作为 cell 最后一行表达式即可，**不要**多余包裹：

- Polars DataFrame / LazyFrame
- Pandas DataFrame / Series
- Altair Chart
- Matplotlib Figure
- 基本类型 (str, int, list, dict)

只需将表达式作为 cell 的最后一行或放入 `mo.vstack()` 即可：

```python
@app.cell
def _(df, pl):
    # DataFrame 直接返回，marimo 自动渲染（含分页、排序）
    df.group_by("category").agg(pl.len())
    return
```

### `mo.ui.table()` 的唯一使用场景

`mo.ui.table()` **仅在需要把用户的行选择暴露为 reactive 值时使用**——选中的行通过 `.value` 传给下游 cell 触发计算。普通 DataFrame 自动渲染也有分页和选择 UI，但选择结果不会传递到其他 cell。

```python
# 需要 reactive 行选择时才用 mo.ui.table
@app.cell
def _(df):
    table = mo.ui.table(df)
    table
    return table,

@app.cell
def _(table):
    # table.value 是用户选中的行，选择变化时自动重跑
    table.value.describe()
    return
```

**不需要 reactive 行选择 → 直接放 DataFrame 表达式，不用 `mo.ui.table()`。**
