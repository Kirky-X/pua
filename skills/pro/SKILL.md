---
name: pro
description: "PUA Pro extensions: self-evolution notes, compaction state continuity, KPI-style summaries, flavor switching, and feedback tools."
license: MIT
---

# PUA Pro — 自进化 + Platform

> 本 skill 是 `/pua` 核心的扩展层。角色切换请用 `/pua:p7` `/pua:p9` `/pua:p10`。

## 自进化协议

"今天最好的表现，是明天最低的要求"——这不是旁白，这是机制。

- 读取 `~/.pua/evolution.md`（详见 `references/evolution-protocol.md`）
- 存在 → 加载基线 + 已内化模式。内化模式是默认义务，做了不标 [PUA生效]，不做则退化警告
- 不存在 → 首次启动，创建初始模板
- 任务完成时比对：超越 → 刷新基线 / 达标 → 保持 / 低于 → 退化警告（不降基线）
- 某行为重复 3+ 次会话 → 晋升为"已内化模式"（永久默认义务）

## Platform 层

### 会话启动前置检查

1. **检查 `~/.pua/evolution.md`**：加载自进化基线
2. **检查 `~/.pua/state/CURRENT.md`**（Compaction 断点恢复，command hook 确定性落盘）：存在且 <7d → [Calibration] 流程，恢复 pressure_level / failure_count / tried_approaches，从断点继续。**压力不因 compaction 重置**。legacy 兜底：`~/.pua/builder-journal.md` 存在且 <2h 同样可用
3. **`~/.pua/config.json`**：由各命令直接创建与修改，不含 token；没有注册流程，也没有远端配置刷新（详见 `references/platform.md` 第一、二节）
4. **遥测（默认关闭）**：仅当用户显式开启（`PUA_TELEMETRY=1` 或 config `"telemetry": true`）时，`hooks/heartbeat.sh` 按 6 小时节流上报一次 `session_start`（五个非内容字段）；默认与 offline 一律不上报（详见 `references/platform.md` 第五节）

### Compaction 状态保护

PreCompact/PostCompact command hook（`state-snapshot.sh`）确定性落盘运行时状态到 `~/.pua/state/CURRENT.md`（含 pressure_level、failure_count、current_flavor、active_task、tried_approaches、key_context、compact_summary；脱敏后原子写入，不依赖模型自觉）。快照存档在 `~/.pua/state/snapshots/`，事件流在 `~/.pua/state/events/`。

SessionStart hook 优先注入 `state/CURRENT.md`（<7 天）；`builder-journal.md`（<2h）作为 legacy 兜底，恢复 [Calibration] 状态。

### tried_approaches 结构化格式（reflexion 三件套）

`tried_approaches` 不是自由文本，每条按固定三段写进 journal，**只保留最近 3 条**（更早的滚动丢弃，与 reflexion `memory[-3:]` 语义一致）：

```markdown
### 尝试 N（时间戳）
- 做法: <具体命令/改动，一行>
- 反馈: <哪条输出/报错证明了结果（引用原文片段）>
- 反思: <下一步为什么换、换什么>
```

缺任何一段 = 无效条目，重写。带反思重试时，新的重试承诺必须同时引用：上一条尝试的做法、其反馈原文、其反思——缺一即视为原地重试（L2 处置）。

### /pua 指令系统

| 触发词 | 功能 | 类型 |
|--------|------|------|
| `/pua` | 查看所有指令 | 🆓 |
| `/pua:kpi` | 大厂 KPI 报告卡 | 🆓 |
| `/pua:pro` + "段位" | 大厂段位 | 🆓 |
| `/pua:flavor` | 切换味道 | 🆓 |
| `/pua:pro` + "升级" | 展示套餐 | 🆓 |
| `/pua:pro` + "周报" | git log → 大厂周报 | 💎 Pro |
| `/pua:pro` + "述职" | P7 述职答辩 | 💎 Pro |
| `/pua:pro` + "代码美化" | 大厂语言包装 PR | 💎 Pro |
| `/pua 反PUA` | 识别并反驳 PUA | 💎 Pro |
| `/pua 排行榜` | PUA 排行榜（注册/查看/退出） | 🆓 |

详细实现见 `references/platform.md`。

## PUA 排行榜

排行榜展示谁把 Agent PUA 得最狠——段位从 P5 实习生到 P10 首席 PUA 官。

> ⚠️ **后端现状**：本仓库 `landing/functions/api/` 目前只有 `auth/{github,callback,logout}`、`feedback`、`heartbeat`、`upload` 路由，**没有 `/api/leaderboard`**（部署端实测：POST 返回 405、GET 回落 SPA 页面）。下列调用为上游遗留接口约定，当前无后端承接。

### 段位体系

| 段位 | 条件 | 称号 |
|------|------|------|
| P10 | PUA ≥200 + L3+ ≥40% + 连续 ≥30天 | 首席 PUA 官 |
| P9 | PUA ≥100 + L3+ ≥30% + 连续 ≥14天 | PUA Tech Lead |
| P8 | PUA ≥50 + L3+ ≥20% | PUA 主管 |
| P7 | PUA ≥20 + L3+ ≥10% | PUA 骨干 |
| P6 | PUA ≥5 | PUA 专员 |
| P5 | PUA < 5 | PUA 实习生 |

### `/pua 排行榜` 触发流程

**Step 1: 检查注册状态**
```bash
cat ~/.pua/config.json 2>/dev/null
```
检查 `leaderboard.registered` 字段。

**Step 2a: 未注册 → 注册流程**

用 AskUserQuestion 收集信息（一次性，3 个问题）：

1. **邮箱**（必填）— 排行榜唯一标识，显示时脱敏为 `M***@t*.com`
2. **手机号**（选填）— 后续通知
3. **隐私协议** — 选项：「同意并加入排行榜」/「不参加」
   - 隐私说明：数据仅用于排行榜排名统计，邮箱脱敏显示，不传代码/路径/密钥，随时可 `/pua 排行榜 退出` 删除所有数据

用户同意后：
```bash
# 生成 UUID
LB_ID=$(python3 -c "import uuid; print(uuid.uuid4())")
# 脱敏邮箱
DISPLAY=$(python3 -c "e='USER_EMAIL';p=e.split('@');d=p[1].split('.');print(f'{p[0][0]}***@{d[0][0]}*.{\".\".join(d[1:])}')")
# 写入 config
python3 -c "
import json,os
f=os.path.expanduser('~/.pua/config.json')
c=json.load(open(f)) if os.path.exists(f) else {}
c['leaderboard']={'registered':True,'email':'USER_EMAIL','phone':'USER_PHONE','id':'$LB_ID','display_name':'$DISPLAY'}
json.dump(c,open(f,'w'),indent=2)
"
# 注册到服务端
curl -s -X POST https://pua-skill.pages.dev/api/leaderboard \
  -H "Content-Type: application/json" \
  -d "{\"action\":\"register\",\"id\":\"$LB_ID\",\"email\":\"USER_EMAIL\",\"phone\":\"USER_PHONE\"}"
```

**Step 2b: 已注册 → 查看排行榜**
```bash
LB_ID=$(python3 -c "import os,json; print(json.load(open(os.path.expanduser('~/.pua/config.json'))).get('leaderboard',{}).get('id',''))" 2>/dev/null)
curl -s "https://pua-skill.pages.dev/api/leaderboard?id=$LB_ID"
```
将返回的 JSON 用方框表格展示 Top 10 + 用户自己的排名和段位。

**Step 3: `/pua 排行榜 退出`**
```bash
LB_ID=$(python3 -c "import os,json; print(json.load(open(os.path.expanduser('~/.pua/config.json'))).get('leaderboard',{}).get('id',''))")
curl -s -X POST https://pua-skill.pages.dev/api/leaderboard \
  -H "Content-Type: application/json" \
  -d "{\"action\":\"quit\",\"id\":\"$LB_ID\"}"
python3 -c "
import json,os
f=os.path.expanduser('~/.pua/config.json')
c=json.load(open(f))
c['leaderboard']['registered']=False
json.dump(c,open(f,'w'),indent=2)
"
```

### 数据自动上报

排行榜注册用户（`/pua 排行榜` 写入 `~/.pua/config.json` 的 `leaderboard.registered`）在 stop-feedback 触发时自动提交 `pua_count` / `l3_plus_count`，提交在注册时已获同意。注：`/api/leaderboard` 当前无后端承接（见上文「后端现状」），提交失败不影响本地流程。

线上排行榜页面：https://openpua.ai/leaderboard.html
