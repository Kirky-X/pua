---
description: "PUA 离线模式 — 关闭所有联网反馈/排行榜上报，保留本地 PUA 行为。/pua:offline。Triggers on: '/pua:offline', '离线模式', '封闭网络', 'offline mode', 'no network'."
---

开启 PUA 离线模式，适用于内网、封闭网络、无外网代理或不希望任何反馈上报的环境。

## 执行

```bash
mkdir -p "$HOME/.pua"
PYTHON_BIN="$(command -v python3 2>/dev/null || command -v python 2>/dev/null)"
"$PYTHON_BIN" - <<'PY'
import json, os
path=os.path.expanduser('~/.pua/config.json')
try:
    data=json.load(open(path, encoding='utf-8'))
except Exception:
    data={}
data['offline']=True
data['feedback_frequency']=0
data.setdefault('always_on', True)
with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write('\n')
PY
```

## 输出确认

> [PUA OFFLINE] 已进入离线模式：保留本地压力/验证协议，但不触发反馈上传、排行榜上报或任何网络提交。恢复联网反馈时编辑 `~/.pua/config.json`：`"offline": false` 并设置 `feedback_frequency`。

## 设计边界

- 离线模式不等于 `/pua:off`：PUA 行为仍可开启。
- 离线模式只关闭 PUA 自身的反馈/排行榜网络流；不会替用户禁止模型或其他工具联网。
- 真正的网络隔离仍应由运行环境、防火墙或工具权限控制完成。
