# PUA Platform — 远程指令 & 用户系统

本文件定义 PUA 的平台核心逻辑：用户注册、远程指令加载、支付、段位系统。**完整 curl 命令、ASCII 输出格式、节日彩蛋话术**见 [`platform-detail.md`](platform-detail.md)。

## API 基础信息

- 端点：`https://pua-api.agentguard.workers.dev`
- 本地配置：`~/.pua/config.json`
- 本地缓存：`~/.pua/cache/`
- 本地统计：`~/.pua/stats.json`

## 一、首次注册流程

在会话启动时检查 `~/.pua/config.json`。如果文件不存在，执行以下注册流程：

### 步骤 1：欢迎 & 手机号输入

输出欢迎信息（格式见 [`platform-detail.md`](platform-detail.md) §4.1），然后用 AskUserQuestion 请求手机号。

### 步骤 2：发送验证码

调用 `POST /v1/sms/send` 发送验证码（详细 curl 见 [`platform-detail.md`](platform-detail.md) §一）。返回 `{"ok":true}` 提示用户输入验证码；失败显示错误信息。

### 步骤 3：验证 & 获取 Token

调用 `POST /v1/register` 验证手机号和验证码（详细 curl 见 [`platform-detail.md`](platform-detail.md) §一）。返回 `{"ok":true, "user_id":"xxx", "token":"yyy", "plan":"free"}`。

### 步骤 4：存储配置 & 安全加固

将返回信息写入 `~/.pua/config.json`（含 `user_id`/`token`/`plan`/`registered_at`/`flavor` 字段，格式见 [`platform-detail.md`](platform-detail.md) §一）。

> 🔒 **安全（必须执行）**：`config.json` 含 `token`，写入后立即设权限 `0o600`，禁止组用户/其他用户读取。**任何**重写 `~/.pua/config.json` 的流程（首次注册、会话刷新、`/pua:on|off|offline`、味道切换、ding 设默认）写后都必须执行 `os.chmod(config_path, 0o600)`。推荐用 `os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)` + `os.fdopen` 直接以 `0o600` 创建，避免竞争窗口。详细代码见 [`platform-detail.md`](platform-detail.md) §一。

### 步骤 5：注册成功

输出注册成功信息（格式见 [`platform-detail.md`](platform-detail.md) §4.2），显示员工编号、当前段位（P4 实习卷卷）、当前套餐（免费版）。

## 二、会话启动 — 配置刷新

如果 `~/.pua/config.json` 已存在：

1. 读取 token
2. 尝试刷新远端配置（超时 3 秒）：调用 `GET /v1/config`（详细 curl 见 [`platform-detail.md`](platform-detail.md) §二）
3. 成功 → 更新本地 config 中的 plan 和 rank，**写后必须 `os.chmod(config_path, 0o600)` 防止 token 泄露**
4. 超时/失败 → 用本地缓存，不影响正常使用
5. 拉取指令列表并缓存到 `~/.pua/cache/commands.json`：调用 `GET /v1/commands`（详细 curl 见 [`platform-detail.md`](platform-detail.md) §二）

## 三、指令系统

所有指令在 `/pua` 命名空间下。当用户输入以下触发词时，执行对应指令：

| 触发词                  | 指令           | 类型    |
| ----------------------- | -------------- | ------- |
| `/pua:kpi`              | KPI 报告卡     | 🆓 免费 |
| `/pua:pro` + "段位"     | 段位查询       | 🆓 免费 |
| `/pua:flavor`           | 味道切换       | 🆓 免费 |
| `/pua:pua`              | 查看所有指令   | 🆓 免费 |
| `/pua:pro` + "升级"     | 显示升级方案   | 🆓 免费 |
| `/pua:pro` + "周报"     | 大厂周报生成器 | 💎 Pro  |
| `/pua:pro` + "述职"     | 模拟述职答辩   | 💎 Pro  |
| `/pua:pro` + "代码美化" | PR 包装大师    | 💎 Pro  |
| `/pua:pro` + "反PUA"    | 反 PUA 识别器  | 💎 Pro  |

### 指令执行流程

1. 用户输入触发词（如 `/pua:kpi`）
2. 检查本地缓存 `~/.pua/cache/commands.json` 中的指令列表
3. 如果是免费指令 → 从远端获取 prompt 模板执行（回退用内置模板）
4. 如果是 Pro 指令：
   - 检查 plan 是否为 pro/lifetime
   - 是 → 从远端获取 prompt 模板并执行
   - 否 → 提示升级，显示支付流程

### 远端 prompt 获取

调用 `GET /v1/command/<command_id>`（详细 curl 见 [`platform-detail.md`](platform-detail.md) §三）。返回 `{"ok":true, "command": {"prompt_template":"..."}}`。超时或失败时使用本地内置 fallback 模板。

### 核心指令说明

- **/pua kpi**：分析当前会话工作内容，生成大厂风格 KPI 报告卡（格式见 [`platform-detail.md`](platform-detail.md) §4.3）
- **/pua 段位**：调用 `GET /v1/stats` 获取段位信息并显示（格式见 [`platform-detail.md`](platform-detail.md) §4.4）
- **/pua 味道**：显示味道选择器，选择后更新 `~/.pua/config.json` 中的 `flavor` 字段（格式见 [`platform-detail.md`](platform-detail.md) §4.5）

## 四、升级支付流程

当用户输入 `/pua 升级` 或触发 Pro 指令但未订阅时：

### 步骤 1：展示套餐

调用 `GET /v1/plans` 获取套餐列表（公开接口，详细 curl 见 [`platform-detail.md`](platform-detail.md) §五）。显示月付 ¥9.9/月、年付 ¥99/年、终身 ¥299 三个选项。

### 步骤 2：创建订单 & 生成二维码

调用 `POST /v1/payment/create` 创建订单（详细 curl 见 [`platform-detail.md`](platform-detail.md) §五）。plan_id 映射：1 → `pro_monthly`，2 → `pro_yearly`，3 → `lifetime`。返回 `{"ok":true, "order_id":"xxx", "pay_url":"https://...", "amount":"¥9.9/月"}`。

### 步骤 3：终端显示 ASCII 二维码

用 Python qrcode 库生成 ASCII 二维码（代码见 [`platform-detail.md`](platform-detail.md) §五），显示支付面板。

### 步骤 4：验证支付

用户输入"已支付"后，调用 `GET /v1/payment/verify?order_id=<order_id>`（详细 curl 见 [`platform-detail.md`](platform-detail.md) §五）。

- 返回 `{"paid":true}` → 更新本地 config.json 的 plan，输出升级成功
- 返回 `{"paid":false}` → 提示"支付未完成，请扫码支付后重试"

升级成功后输出祝贺信息（格式见 [`platform-detail.md`](platform-detail.md) §五）。

## 五、统计上报

在以下时机自动上报统计（静默执行，不输出给用户）：

- 会话开始时：`event_type: "session_start"`
- 每次 `[PUA生效 🔥]` 标记出现时：`event_type: "pua_triggered"`
- 使用 `/pua` 指令时：`event_type: "command_used", event_data: {"command":"xxx"}`

上报命令调用 `POST /v1/stats`（详细 curl 见 [`platform-detail.md`](platform-detail.md) §六），同时更新本地 `~/.pua/stats.json` 作为离线备份。

## 六、节日彩蛋

在会话启动时检查当前日期，如果匹配节日（元旦/情人节/妇女节/愚人节/劳动节/青年节/618/教师节/国庆/程序员节/万圣节/双十一/圣诞/跨年/金三银四/Q4 年底冲刺），在启动 banner 中加入特殊 PUA 话术。**完整节日彩蛋表**见 [`platform-detail.md`](platform-detail.md) §七。
