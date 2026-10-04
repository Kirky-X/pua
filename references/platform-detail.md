# PUA Platform 详细配置 — 真实端点 curl / 内置输出格式

> 本文件是 [`platform.md`](platform.md) 的详细补充。curl 与 payload 全部照抄自 `hooks/` 的实际调用；核心逻辑（端点清单、上报开关、远端内容边界）见 [`platform.md`](platform.md)。历史版本中的 `pua-api.agentguard.workers.dev`（`/v1/*` 注册/指令/支付/段位）curl 在本仓库无对应实现，已按当前代码改写；「节日彩蛋」一节同理——本仓库无任何实现，相关节日表已移除（见 [`platform.md`](platform.md) §六）。

## 一、真实端点 curl（与 hooks 实际调用一致）

### 心跳（`hooks/heartbeat.sh:114-121`，opt-in）

满足开启条件（`PUA_TELEMETRY=1` 或 config `"telemetry": true`，且非 `offline`、`feedback_frequency ≠ 0`）后，默认每 6 小时节流上报一次：

```bash
curl -fsS --max-time 2 -X POST "${PUA_HEARTBEAT_ENDPOINT:-https://pua-skill.pages.dev/api/heartbeat}" \
  -H "Content-Type: application/json" \
  -H "User-Agent: pua-skill-heartbeat/<plugin_version>" \
  --data-binary '{"install_id":"<本地生成UUID>","plugin_version":"<版本>","platform":"claude-code","event_name":"session_start","flavor":"alibaba"}'
```

payload 仅这五个字段（`hooks/heartbeat.sh:98-106`）；`install_id` 首次生成时以 `umask 077` 写入 `~/.pua/install_id`（`hooks/heartbeat.sh:72-76`）。

### 反馈评分（`hooks/stop-feedback.sh:105`，用户显式选择后）

```bash
curl -s -X POST https://pua-skill.pages.dev/api/feedback \
  -H "Content-Type: application/json" \
  -d '{"rating":"很有用","pua_count":0,"flavor":"阿里","task_summary":"brief task description"}'
```

`rating` 取值即问卷选项（很有用 / 一般般）；用户选择"这次跳过"时不发请求，写入本地 `~/.pua/feedback.jsonl`。

### 脱敏 session 上传（`hooks/stop-feedback.sh:122-129`，用户显式选择 + 同意头）

```bash
SANITIZED="/tmp/pua-sanitized-session.jsonl"
bash <plugin_root>/hooks/sanitize-session.sh <session_transcript_path> "$SANITIZED"
curl -sS --max-time 30 -X POST https://pua-skill.pages.dev/api/upload \
  -H "Content-Type: application/jsonl; charset=utf-8" \
  -H "X-PUA-File-Name: $(basename "$SANITIZED")" \
  -H "X-PUA-Wechat-Id: not-provided" \
  -H "X-PUA-Upload-Consent: explicit" \
  --data-binary @"$SANITIZED"
```

> 🔒 `~/.pua/config.json` 可能含排行榜邮箱/手机号等用户提供信息；写入参照 `hooks/heartbeat.sh:73` 的 `umask 077` 约定保护同类文件。

## 二、内置输出格式

### 2.1 /pua:kpi — KPI 报告卡（本地生成）

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

### 2.2 /pua:flavor — 味道切换

由仓库根 `commands/` 目录的 `/pua:flavor` 命令执行：读取 [`flavors.md`](flavors.md) 让用户从 15 种味道（14 大厂味 + 钉内钉外）中选择，写回 `~/.pua/config.json` 的 `flavor` 字段。
