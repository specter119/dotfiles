# Friendly Python

本文基于 Frost Ming “friendly python” 标签下的文章，整理出偏向工程实践的开发范式、规范与典型好/坏代码范式示例。重点是“对使用者友好 + 对维护者友好”，并强调在 Python 中利用语言特性与生态扩展点进行合理抽象。

## 资料来源

- <https://frostming.com/posts/2021/07-07/friendly-python-1/>
- <https://frostming.com/posts/2021/07-23/friendly-python-2/>
- <https://frostming.com/posts/2022/friendly-python-oop/>
- <https://frostming.com/posts/2024/friendly-python-reuse/>
- <https://frostming.com/posts/2025/friendly-python-port/>
- <https://frostming.com/posts/2021/11-23/advanced-argparse/>

## 开发范式与规范

### 1) 以“用户体验”倒推 API 设计

- 优先提供合理默认值，让 Quick Start 在不看文档时也能跑通。
- 把必填信息收敛为最少参数，隐藏复杂对象的显式组装。
- 用上下文管理器或统一入口对象隐藏资源管理细节。
- 支持“由简入繁”：默认简单路径，复杂需求可显式扩展。

### 2) 扩展点收敛，减少修改面

- 新增策略/命令/实现时，尽量收敛到“一个改动点”。
- 用注册中心/插件表替代 if-else 链。
- 如果引入“魔法”（自动扫描/动态导入），需评估可读性与可调试性。

### 3) 构造方式清晰、对象初始化完整

- 不推荐“实例化后再 load”的半成品对象；用 classmethod 构造。
- 多种输入来源（env/file/explicit）用不同构造入口而非 **init** flag。
- 避免为“复用”而暴露不必要的类或函数，减少导入负担。

### 4) 显式优于隐式，避免滥用元编程

- **getattr** 兜底所有字段会弱化可发现性、补全与类型约束。
- 元类/黑魔法若引入额外可见接口，会污染用户心智模型。
- 用描述符、显式字段或注册表等方式保持结构可见。

### 5) 复用生态扩展点，最小侵入

- 扩展第三方库优先走官方 hook/adapter/auth 等扩展点。
- 避免自建 Request/Response 对象再“转回去”，减少属性复制。
- 仅在扩展点不足时才考虑继承/重载/monkey patch。

### 6) 跨语言移植要“重新设计调用方式”

- 去掉语言限制导致的模式（例如 builder、过度回调）。
- 用 Python 自然范式替代：关键字参数、上下文管理器、装饰器、生成器。
- 先设计调用方式，再决定实现细节（自顶向下）。

### 7) CLI 与可扩展命令体系

- argparse 适合做 OOP 化命令结构与可扩展子命令。
- 子命令绑定处理函数，参数复用通过“参数对象”抽象完成。

## 典型好/坏代码范式示例

### 示例 1：扩展点收敛（策略/插件）

**Bad**：多处 if-else，新增实现要改多个位置。

```python
class NewsGrabber:
    def get_news(self, source=None):
        if source is None:
            return chain(HNSource().iter_news(), V2Source().iter_news())
        if source == "HN":
            return HNSource().iter_news()
        if source == "V2":
            return V2Source().iter_news()
        raise ValueError(f"Unknown source: {source}")
```

**Good**：注册中心 + 单一改动点。

```python
SOURCE_REGISTRY = {}

def register(cls):
    SOURCE_REGISTRY[cls.name] = cls()
    return cls

@register
class HNSource:
    name = "HN"

@register
class V2Source:
    name = "V2"

class NewsGrabber:
    def get_news(self, source=None):
        if source is None:
            return chain.from_iterable(s.iter_news() for s in SOURCE_REGISTRY.values())
        try:
            return SOURCE_REGISTRY[source].iter_news()
        except KeyError as exc:
            raise ValueError(f"Unknown source: {source}") from exc
```

### 示例 2：API 默认值 + 资源管理

**Bad**：强制拼装多个对象 + 手动关闭。

```python
auth = AwesomeBasicAuth(user, password)
conn = AwesomeTCPConnection(host, port, timeout, retry_times, auth)
client = AwesomeClient(conn, type="test", scope="read")
print(client.get_resources())
conn.close()
```

**Good**：默认值 + 上下文管理器。

```python
client = AwesomeClient(type="test", scope="read", auth=(user, password))
with client.connect():
    print(client.get_resources())
```

### 示例 3：构造方式清晰

**Bad**：**init** 里用 flag 控制路径，参数互斥不透明。

```python
class Settings:
    def __init__(self, **kwargs):
        if kwargs.get("from_env"):
            self._load_env()
        elif kwargs.get("from_file"):
            self._load_file(kwargs["from_file"])
        else:
            self._load_kwargs(kwargs)
```

**Good**：不同来源用 classmethod 构造。

```python
class Settings:
    def __init__(self, db_user, db_password, db_host="localhost", db_port=3306):
        self.db_user = db_user
        self.db_password = db_password
        self.db_host = db_host
        self.db_port = db_port

    @classmethod
    def from_env(cls):
        return cls(
            db_user=os.getenv("DB_USER"),
            db_password=os.getenv("DB_PASSWORD"),
        )

    @classmethod
    def from_file(cls, path):
        data = load_config(path)
        return cls(**data)
```

### 示例 4：显式字段 vs 动态魔法

**Bad**：**getattr** 兜底所有字段，结构不可见。

```python
class Settings:
    def __getattr__(self, name):
        return os.environ["CONFIG_" + name.upper()]
```

**Good**：描述符 + 显式字段。

```python
class ConfigItem:
    def __set_name__(self, owner, name):
        self.name = name
        self.env_name = "CONFIG_" + name.upper()

    def __get__(self, instance, owner):
        if instance is None:
            return self
        return instance._data.get(self.name) or os.getenv(self.env_name)

class Settings:
    db_url = ConfigItem()
    db_password = ConfigItem()
```

### 示例 5：复用库扩展点

**Bad**：自建 request 再转换回 requests。

```python
req = CustomRequest(api_info, body)
SignerV4.sign(req, credentials)
url = req.build()
resp = requests.post(url, headers=req.headers, data=req.body)
```

**Good**：使用 requests.auth 作为签名扩展点。

```python
class VolcAuth(requests.auth.AuthBase):
    def __init__(self, service_info, credentials):
        self.service_info = service_info
        self.credentials = credentials

    def __call__(self, r):
        sign_request(r, self.service_info, self.credentials)
        return r

resp = requests.post(url, json=payload, auth=VolcAuth(service_info, credentials))
```

### 示例 6：移植时重新设计调用方式

**Bad**：把 JS 回调式 API 直接翻译。

```python
def download_file(url, on_success, on_error, on_complete):
    ...
```

**Good**：用 Python 结构化控制流。

```python
try:
    data = await download_file(url)
except Exception:
    handle_error()
finally:
    cleanup()
```

### 示例 7：CLI 扩展性

**Bad**：click 继承命令时只能 monkey patch callback。

```python
def wrap_callback(cb):
    def new_cb(*args, **kwargs):
        if kwargs.get("verbose"):
            print("verbose")
        return cb(*args, **kwargs)
    return new_cb
```

**Good**：argparse + Command 类 + set_defaults(handle=...).

```python
class Command:
    name = ""
    arguments = []

    def add_arguments(self, parser):
        for arg in self.arguments:
            arg.add_to_parser(parser)

    def handle(self, args):
        raise NotImplementedError

class Argument:
    def __init__(self, *args, **kwargs):
        self.args = args
        self.kwargs = kwargs

    def add_to_parser(self, parser):
        parser.add_argument(*self.args, **self.kwargs)

subparsers = parser.add_subparsers()
for cmd_cls in COMMANDS:
    cmd = cmd_cls()
    sub = subparsers.add_parser(cmd.name)
    sub.set_defaults(handle=cmd.handle)
    cmd.add_arguments(sub)
```

## 速查清单

- 能否新增功能只改一个点？
- API 是否有合理默认值？是否隐去不必要对象？
- 复杂度是否“由简入繁”，默认路径最轻？
- 是否优先使用生态扩展点？
- 是否为了炫技牺牲了显式性与可维护性？
- 移植代码是否重新设计了调用方式？
  :wrap_callback
