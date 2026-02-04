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
