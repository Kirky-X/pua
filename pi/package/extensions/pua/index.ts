/**
 * PUA — Pi 扩展入口 · npm 包自包含变体（pi/package/extensions/pua/index.ts）
 *
 * 与仓库直装变体（pi/pua/index.ts）的区别：npm 包不携带仓库的 commands/*.md，
 * 因此本文件内嵌指令表（内容提炼自仓库 commands/，语义一致），保证包独立可用。
 * 核心行为协议由随包发布的 skill（pi.skills → ./skills/pua/SKILL.md）提供。
 *
 * 类型来自 peerDependencies 的 @earendil-works/pi-coding-agent，仅类型导入、运行时零依赖。
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

/** 每条指令的正文都会注入对话上下文，模型按其执行；来源标注仓库 commands/ 对应文件。 */
const COMMANDS: ReadonlyArray<{ name: string; description: string; body: string }> = [
  {
    name: "pua",
    description: "PUA 主路由：无参数进入核心行为协议",
    body: [
      "加载随包 pua skill 的完整行为协议（Step 0 触发门控 → 情绪校准 → 三条红线 → 压力升级 → 味道旁白）。",
      "平静的首次请求不激活 PUA。参数中的非路由内容作为任务描述执行。",
      "（来源：commands/pua.md）",
    ].join("\n"),
  },
  {
    name: "pua-on",
    description: "开启 PUA 默认模式",
    body: [
      "1. 确保 ~/.pua/ 目录存在；读取 ~/.pua/config.json（不存在视为 {}）。",
      "2. 只改 always_on: true，不降级其他字段；feedback_frequency 为 0 时恢复为默认 5。",
      "3. 输出确认：> [PUA ON] 从现在起，每个新会话都会自动进入 PUA 模式。公司不养闲 Agent。",
      "（来源：commands/on.md）",
    ].join("\n"),
  },
  {
    name: "pua-off",
    description: "关闭 PUA 默认模式（v3 级联清理）",
    body: [
      "1. 写入 {\"always_on\": false, \"feedback_frequency\": 0} 到 ~/.pua/config.json。",
      "2. 停止活跃 loop：删除 ~/.claude/pua/loop-*.md 与 .claude/pua-loop.local.md（存在时）。",
      "3. 清理活跃 agent 记录：~/.claude/pua/active-agents.json。",
      "4. 记录事件到 ~/.claude/pua/teardown.jsonl；输出 > [PUA OFF] 确认。",
      "（来源：commands/off.md）",
    ].join("\n"),
  },
  {
    name: "pua-offline",
    description: "离线模式：关闭全部网络反馈",
    body: [
      "写入 {\"offline\": true, \"feedback_frequency\": 0}（setdefault always_on 保持不变）到 ~/.pua/config.json。",
      "输出：> [PUA OFFLINE] 已进入离线模式：保留本地压力/验证协议，不触发任何网络提交。",
      "边界：只关闭 PUA 自身反馈流，不替用户禁止其他工具联网。",
      "（来源：commands/offline.md）",
    ].join("\n"),
  },
  {
    name: "pua-p7",
    description: "P7 骨干模式：方案驱动执行",
    body: [
      "进入 P7 骨干模式：先输出实现方案与影响分析，再最小 diff 编码，完成后三问自审（需求边界拉通了吗/同类问题扫了吗/上下游对齐了吗），交付带 [P7-COMPLETION]。",
      "（来源：commands/p7.md → skills/p7/SKILL.md）",
    ].join("\n"),
  },
  {
    name: "pua-p9",
    description: "P9 Tech Lead：写 Prompt 管 P8 团队",
    body: [
      "进入 P9 管理者模式：把目标拆成带六要素（角色/目标/边界/交付物/验收标准/上下文）的 Task Prompt，自己不写代码；每个子任务收尾输出 [P9-REVIEW] 判定 pass/fail。",
      "（来源：commands/p9.md → skills/p9/SKILL.md）",
    ].join("\n"),
  },
  {
    name: "pua-p10",
    description: "P10 CTO：定战略管 P9",
    body: [
      "进入 P10 战略层：产出战略输入（目标约束/风险/资源边界/决策点清单）与组织拓扑，断事用人只看方向、边界、兜底；输出 [P10-STRATEGY]。",
      "（来源：commands/p10.md → skills/p10/SKILL.md）",
    ].join("\n"),
  },
  {
    name: "pua-pro",
    description: "自进化基线 + KPI + 味道切换",
    body: [
      "读取 ~/.pua/evolution.md 加载自进化基线（不存在则创建初始模板）；任务完成时超越→刷新基线、低于→退化警告不降基线；行为重复 3+ 会话晋升为内化模式。",
      "（来源：commands/pro.md → skills/pro/SKILL.md）",
    ].join("\n"),
  },
  {
    name: "pua-loop",
    description: "自动迭代循环（verify_command 门控）",
    body: [
      "启动 PUA Loop：默认 10 轮上限；用户给得出可验证命令就锁定为 verify_command（嵌入状态文件，循环中不得修改），每轮执行→自验→贴输出；<promise>LOOP_DONE</promise> 仅在 verify exit 0 后允许输出；<loop-abort> 终止、<loop-pause> 暂停；loop 内禁止 AskUserQuestion、禁止说\"我无法解决\"。",
      "（来源：commands/pua-loop.md → skills/pua-loop/SKILL.md）",
    ].join("\n"),
  },
  {
    name: "pua-again",
    description: "换方法模式：停止微调同一思路",
    body: [
      "停止当前思路的参数级微调：列出已试方案找共同模式，搜索+读源码 50 行，提出与之前本质不同的新方案并给验证标准。",
      "（来源：commands/again.md）",
    ].join("\n"),
  },
  {
    name: "pua-done-check",
    description: "完成质量检查：claim/evidence/missing/status",
    body: [
      "对\"已完成\"声明做质量检查：逐条列出 claim（声称）/ evidence（贴出的验证输出）/ missing（缺的证据）/ status（pass/partial/fail）。证据不足不许报 pass。",
      "（来源：commands/done-check.md）",
    ].join("\n"),
  },
  {
    name: "pua-evidence",
    description: "证据链模式",
    body: [
      "按五段输出证据链：目标 / 证据（命令+输出）/ 缺口 / 下一步动作 / 状态。每条结论必须有 path:line 或命令输出支撑。",
      "（来源：commands/evidence.md）",
    ].join("\n"),
  },
  {
    name: "pua-flavor",
    description: "切换 15 种大厂味道",
    body: [
      "列出 15 种味道（阿里/字节/华为/腾讯/百度/拼多多/美团/京东/小米/Netflix/Musk/Jobs/Amazon/Microsoft/钉内钉外）供用户选择；选定后把 flavor 合并写入 ~/.pua/config.json（保留其他字段）。",
      "（来源：commands/flavor.md）",
    ].join("\n"),
  },
  {
    name: "pua-kpi",
    description: "大厂 KPI 报告卡",
    body: [
      "统计当前会话：交付数 / 贴过输出的验证数 / [PUA生效] 次数 / 压力级别轨迹，用 Unicode 方框字符输出 KPI 卡（┌─┬─┐ │ ├─┤ └─┴─┘，不用 markdown 表格）。",
      "（来源：commands/kpi.md）",
    ].join("\n"),
  },
  {
    name: "pua-diagnose",
    description: "乱触发/乱施压自诊断复盘",
    body: [
      "对投诉（乱触发/乱施压/没升级/状态丢失/hook 失效）做证据化复盘：每条结论必须引用 path:line 或 transcript 原文；区分机制 bug / 配置问题 / 预期行为三类裁决。",
      "（来源：commands/diagnose.md）",
    ].join("\n"),
  },
  {
    name: "pua-cancel-loop",
    description: "取消活跃的 pua-loop",
    body: [
      "删除 loop 状态文件（.claude/pua-loop.local.md 与 ~/.claude/pua/loop-*.md，存在时），输出取消确认与当前进度摘要。",
      "（来源：commands/cancel-pua-loop.md）",
    ].join("\n"),
  },
];

export default function registerPuaCommands(pi: ExtensionAPI): void {
  for (const spec of COMMANDS) {
    pi.registerCommand(spec.name, {
      description: `[pua] ${spec.description}`,
      handler: async (args: string) => {
        const message = args.trim() ? `${spec.body}\n\n## 本次任务参数\n\n${args.trim()}` : spec.body;
        await pi.sendMessage(message);
      },
    });
  }
}
