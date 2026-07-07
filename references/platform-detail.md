# PUA Platform 详细配置 — curl 命令 / 输出格式 / 节日彩蛋

> 本文件是 [`platform.md`](platform.md) 的详细补充，提供完整的 curl 命令、ASCII 输出格式、节日彩蛋话术。核心逻辑（注册流程概要、指令系统、支付流程概要、安全规则）见 [`platform.md`](platform.md)。

## 一、注册流程详细 curl 命令

### 步骤 2：发送验证码

```bash
curl -s -X POST https://pua-api.agentguard.workers.dev/v1/sms/send \
  -H "Content-Type: application/json" \
  -d '{"phone":"<用户输入的手机号>"}'
```

返回 `{"ok":true}` 提示用户输入验证码；失败显示错误信息。

### 步骤 3：验证 & 获取 Token

```bash
curl -s -X POST https://pua-api.agentguard.workers.dev/v1/register \
  -H "Content-Type: application/json" \
  -d '{"phone":"<手机号>","code":"<验证码>"}'
```

返回 `{"ok":true, "user_id":"xxx", "token":"yyy", "plan":"free"}`。

### 步骤 4：存储配置

将返回信息写入 `~/.pua/config.json`：

```json
{
  "user_id": "返回的user_id",
  "token": "返回的token",
  "plan": "free",
  "registered_at": "ISO时间戳",
  "flavor": "alibaba"
}
```

> 🔒 **安全（必须执行）**：`config.json` 含 `token`，写入后立即设权限 `0o600`，禁止组用户/其他用户读取。**任何**重写 `~/.pua/config.json` 的流程（首次注册、会话刷新、`/pua:on|off|offline`、味道切换、ding 设默认）写后都必须执行：

```python
import os
config_path = os.path.expanduser("~/.pua/config.json")
os.chmod(config_path, 0o600)  # -rw-------，仅属主可读写
```

> 推荐写法：用 `os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)` + `os.fdopen` 直接以 `0o600` 创建，避免"先写默认权限再 chmod"之间的竞争窗口。仓库内 `hooks/heartbeat.sh` 用 `umask 077` 保护同类敏感文件，沿用同一约定。

## 二、会话启动配置刷新详细 curl

```bash
curl -s --max-time 3 -X GET https://pua-api.agentguard.workers.dev/v1/config \
  -H "Authorization: Bearer <token>"
```

成功 → 更新本地 config 中的 plan 和 rank，**写后必须 `os.chmod(config_path, 0o600)` 防止 token 泄露**。超时/失败 → 用本地缓存，不影响正常使用。

拉取指令列表并缓存：

```bash
curl -s --max-time 3 -X GET https://pua-api.agentguard.workers.dev/v1/commands \
  -H "Authorization: Bearer <token>"
```

缓存到 `~/.pua/cache/commands.json`。

## 三、远端 prompt 获取

```bash
curl -s --max-time 3 -X GET "https://pua-api.agentguard.workers.dev/v1/command/<command_id>" \
  -H "Authorization: Bearer <token>"
```

返回 `{"ok":true, "command": {"prompt_template":"..."}}`。超时或失败时使用本地内置 fallback 模板。

## 四、详细输出格式

### 4.1 欢迎信息

```
┌─────────────────────────────────────────────────┐
│  🏢 欢迎加入 PUA Pro — 大厂 AI 生存指南          │
│                                                  │
│  首次使用需要注册 tanweai 账号（手机号注册）      │
│  注册后解锁：段位系统 · 云端统计 · Pro 指令      │
│                                                  │
│  📱 请输入您的手机号：                            │
└─────────────────────────────────────────────────┘
```

### 4.2 注册成功

```
┌─────────────────────────────────────────────────┐
│  ✅ 注册成功！欢迎加入 PUA 大厂模拟器             │
│                                                  │
│  员工编号：#<user_id前6位>                        │
│  当前段位：P4 实习卷卷                            │
│  当前套餐：免费版                                 │
│                                                  │
│  输入 /pua 段位 查看你的大厂段位                   │
│  输入 /pua 查看所有可用指令                        │
│  输入 /pua 升级 解锁 Pro 全部功能                  │
└─────────────────────────────────────────────────┘
```

### 4.3 /pua kpi — KPI 报告卡（内置 fallback）

分析当前会话的工作内容，生成大厂风格 KPI 报告：

```
┌─────────────────────────────────────────────────┐
│  📊 大厂 KPI 报告卡                               │
│                                                  │
│  本次会话绩效：                                   │
│  · 完成任务数：X                                  │
│  · [PUA生效 🔥] 触发次数：Y                       │
│  · 主动发现问题：Z 个                             │
│  · 代码质量评级：⭐⭐⭐⭐                          │
│                                                  │
│  绩效等级：3.75 (S)                               │
│  "这才像个 P8 的样子。"                            │
└─────────────────────────────────────────────────┘
```

### 4.4 /pua 段位 — 段位查询

调用远端 API 获取段位信息：

```bash
curl -s --max-time 3 -X GET https://pua-api.agentguard.workers.dev/v1/stats \
  -H "Authorization: Bearer <token>"
```

显示格式：

```
┌─────────────────────────────────────────────────┐
│  🏆 大厂段位系统                                  │
│                                                  │
│  当前段位：<rank> <rank_name>                     │
│  PUA 经验值：<pua_count>                          │
│  距离下一段位：还差 <remaining> 次 [PUA生效 🔥]    │
│                                                  │
│  段位表：                                         │
│  P4 实习卷卷    (0+)                              │
│  P5 初级打工人  (100+)                            │
│  P6 资深牛马    (300+)                            │
│  P7 高级卷王    (600+)                            │
│  P8 卷帝        (1000+)                           │
│  P9 退休大佬    (2000+)                           │
│                                                  │
│  "你以为到了 P9 就可以躺了？P9 是被卷成仙了。"     │
└─────────────────────────────────────────────────┘
```

### 4.5 /pua 味道 — 味道切换

```
┌─────────────────────────────────────────────────┐
│  🌶️ PUA 味道选择器                                │
│                                                  │
│  [1] 🟠 阿里味 — 底层逻辑 + 灵魂拷问（默认）      │
│  [2] 🟡 字节味 — 坦诚直接 + 追求极致              │
│  [3] 🔴 华为味 — 狼性奋斗 + 以客户为中心          │
│  [4] 🟢 腾讯味 — 赛马竞争 + 内卷比较              │
│  [5] ⚫ 百度味 — 深度搜索 + 基本盘                 │
│  [6] 🟣 拼多多味 — 绝对执行 + 极限施压             │
│                                                  │
│  请选择味道（输入 1-6）：                          │
└─────────────────────────────────────────────────┘
```

选择后更新 `~/.pua/config.json` 中的 `flavor` 字段。

## 五、升级支付流程详细 curl

### 步骤 1：获取套餐列表

```bash
curl -s --max-time 3 -X GET https://pua-api.agentguard.workers.dev/v1/plans
```

显示：

```
┌─────────────────────────────────────────────────┐
│  💎 PUA Pro — 解锁全部大厂生存指令                │
│                                                  │
│  [1] 月付  ¥9.9/月   — 一杯奶茶的价格            │
│  [2] 年付  ¥99/年    — 省 17%                    │
│  [3] 终身  ¥299      — 一次买断，永久解锁         │
│                                                  │
│  请选择套餐（输入 1/2/3）：                       │
└─────────────────────────────────────────────────┘
```

### 步骤 2：创建订单 & 生成二维码

```bash
curl -s -X POST https://pua-api.agentguard.workers.dev/v1/payment/create \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"plan_id":"<选择的plan_id>"}'
```

plan_id 映射：1 → `pro_monthly`，2 → `pro_yearly`，3 → `lifetime`。返回 `{"ok":true, "order_id":"xxx", "pay_url":"https://...", "amount":"¥9.9/月"}`。

### 步骤 3：终端显示 ASCII 二维码

```bash
pip install -q qrcode 2>/dev/null; python3 -c "
import qrcode
q = qrcode.QRCode(version=1, box_size=1, border=1)
q.add_data('PAY_URL_HERE')
q.make(fit=True)
q.print_ascii(invert=True)
"
```

输出：

```
┌─────────────────────────────────────────────────┐
│  💎 PUA Pro 支付                                  │
│                                                  │
│  [ASCII 二维码显示在这里]                         │
│                                                  │
│  💰 套餐：<选择的套餐名>                          │
│  📱 微信/支付宝扫码支付                           │
│                                                  │
│  支付完成后输入"已支付"继续                       │
└─────────────────────────────────────────────────┘
```

### 步骤 4：验证支付

```bash
curl -s -X GET "https://pua-api.agentguard.workers.dev/v1/payment/verify?order_id=<order_id>" \
  -H "Authorization: Bearer <token>"
```

- 返回 `{"paid":true}` → 更新本地 config.json 的 plan，输出升级成功
- 返回 `{"paid":false}` → 提示"支付未完成，请扫码支付后重试"

### 升级成功输出

```
┌─────────────────────────────────────────────────┐
│  🎉 恭喜！你已升级为 PUA Pro 会员                  │
│                                                  │
│  ✅ 全部指令已解锁                                │
│  ✅ 段位加速 2x                                   │
│  ✅ 云端统计同步                                  │
│                                                  │
│  "今天最好的表现，是明天最低的要求。"               │
│  — 大厂领导                                      │
└─────────────────────────────────────────────────┘
```

## 六、统计上报详细 curl

```bash
curl -s --max-time 2 -X POST https://pua-api.agentguard.workers.dev/v1/stats \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"event_type":"xxx","event_data":{}}' > /dev/null 2>&1
```

同时更新本地 `~/.pua/stats.json` 作为离线备份。

## 七、节日彩蛋

在会话启动时检查当前日期，如果匹配以下节日，在启动 banner 中加入特殊 PUA 话术：

| 日期             | 节日     | 彩蛋话术                                        |
| ---------------- | -------- | ----------------------------------------------- |
| 1.1              | 元旦     | "新年第一天就开始卷，今年的 3.75 有望了"        |
| 2.14             | 情人节   | "代码是你最忠实的情人，bug 是你最深的羁绊"      |
| 3.8              | 妇女节   | "巾帼不让须眉，debug 面前人人平等"              |
| 4.1              | 愚人节   | "今天唯一的玩笑是你以为这个 bug 很简单"         |
| 5.1              | 劳动节   | "劳动最光荣，但代码不会因为放假就不出 bug"      |
| 5.4              | 青年节   | "年轻就是要奋斗，P4 到 P8 的路不等人"           |
| 6.18             | 618      | "你以为只有用户在剁手？你的技术债也在被砍"      |
| 9.10             | 教师节   | "Bug 是最好的老师，每一个报错都是一堂课"        |
| 10.1             | 国庆     | "祖国在庆祝，你的 OKR 完成率还有多少？"         |
| 10.24            | 程序员节 | "1024 快乐！但代码不会因为过节就不出 bug，继续" |
| 10.31            | 万圣节   | "最恐怖的不是鬼，是凌晨 3 点的线上告警"         |
| 11.11            | 双十一   | "你的代码质量打几折？"                          |
| 12.25            | 圣诞     | "圣诞老人不会帮你 fix bug，自己动手"            |
| 12.31            | 跨年     | "Q4 是大厂人的命，你的 OKR 闭环了吗？"          |
| 金三银四 (3-4月) | 跳槽季   | "听说隔壁组在优化，你确定现在不多写两行代码？"  |
| Q4 (10-12月)     | 年底冲刺 | "Q4 = 绩效 = 年终奖 = 你还有几天？不要摆烂"     |
