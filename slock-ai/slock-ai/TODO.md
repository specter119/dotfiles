# slock-ai TODO

## 用 mihomo 替代 ws-bridge 代理方案

**现状**：当前通过 `ws-bridge.mjs`（`HttpsProxyAgent` + corporate proxy）将 daemon 的 WebSocket 流量隧道到 `api.slock.ai`。API key 在 `local.toml` 的 `slock_proxy` 变量中硬编码了 corporate proxy 地址和认证信息。

**目标**：用 mihomo (Clash Meta) 统一 WSL 的出站代理，所有需要翻墙/走 proxy 的服务都走 mihomo，而不是每个服务单独配一条 bridge。

**优势**：
- 更好的隔离：slock-ai 不需要知道 corporate proxy 细节
- 统一代理策略：mihomo 可以按规则路由（直连 vs proxy）
- 凭证管理集中：proxy 认证在 mihomo 一处配置
- 其他服务也能受益（ollama、各种 CLI 工具等）

**已知障碍**（上次尝试 2025 年 1 月）：
- mihomo 在当前 WSL 环境下无法拉取 proxy provider 订阅（Doggygo、BoostNet 均 0 节点）
- 原因是 mihomo 的 DNS resolver 无法解析外部 DNS（corporate 网络限制）
- 需要先解决 mihomo 自身的 DNS bootstrap 问题（可能需要让 mihomo 也走 corporate proxy 拉订阅）

**可能的方案**：
1. mihomo 配置 corporate proxy 作为 bootstrap proxy，先通过它拉取 provider 订阅
2. 手动导入节点配置（绕过 provider 订阅机制）
3. 在 Windows host 侧运行 mihomo，WSL 通过 host IP 使用
