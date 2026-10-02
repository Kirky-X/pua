/**
 * PUA — Pi (pi.dev) 扩展入口 · 仓库直装变体
 *
 * 本文件位于 pua 插件仓库 `pi/pua/index.ts`，运行时可读同仓库的 `commands/*.md`，
 * 把 Claude Code 的 23 个 `/pua:*` 斜杠命令映射为 Pi 的 `/pua-*` 斜杠命令。
 * npm 包形态（pi/package/extensions/pua/index.ts）为自包含指令表，不改本文件语义。
 *
 * 安装方式见同目录 INSTALL.md：
 *   cp pi/pua/index.ts ~/.pi/extensions/pua/index.ts
 *
 * 依赖：peerDependencies 中的 @earendil-works/pi-coding-agent 仅用于类型，
 * 运行时不导入其值，因此无网络安装也能被 Pi 的 TS 扩展加载器直接执行。
 */
import { readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(HERE, "..", "..");
const COMMANDS_DIR = join(REPO_ROOT, "commands");

/** Claude Code 命令 → Pi 命令的映射表（name 用连字符，对应仓库 commands/<file>）。 */
const COMMANDS: ReadonlyArray<{ name: string; file: string; description: string }> = [
  { name: "pua", file: "pua.md", description: "PUA 主路由：进入核心行为协议或分发子命令" },
  { name: "pua-on", file: "on.md", description: "开启 PUA 默认模式（always_on + 恢复 feedback_frequency）" },
  { name: "pua-off", file: "off.md", description: "关闭 PUA 默认模式（v3 级联清理）" },
  { name: "pua-offline", file: "offline.md", description: "离线模式：保留本地行为，关闭反馈/排行榜上报" },
  { name: "pua-p7", file: "p7.md", description: "P7 骨干模式：方案驱动执行" },
  { name: "pua-p9", file: "p9.md", description: "P9 Tech Lead：写 Prompt 管 P8 团队" },
  { name: "pua-p10", file: "p10.md", description: "P10 CTO：定战略管 P9" },
  { name: "pua-pro", file: "pro.md", description: "自进化基线 + Platform + KPI 工具" },
  { name: "pua-loop", file: "pua-loop.md", description: "自动迭代循环（verify_command 门控）" },
  { name: "pua-again", file: "again.md", description: "换方法模式：停止微调同一思路" },
  { name: "pua-done-check", file: "done-check.md", description: "完成质量检查：claim/evidence/missing/status" },
  { name: "pua-evidence", file: "evidence.md", description: "证据链模式：目标、证据、缺口、动作、状态" },
  { name: "pua-flavor", file: "flavor.md", description: "切换 15 种大厂味道" },
  { name: "pua-kpi", file: "kpi.md", description: "大厂 KPI 报告卡" },
  { name: "pua-ding", file: "ding.md", description: "钉内/钉外味短提醒" },
  { name: "pua-diagnose", file: "diagnose.md", description: "乱触发/乱施压自诊断复盘" },
  { name: "pua-cancel-loop", file: "cancel-pua-loop.md", description: "取消活跃的 pua-loop" },
];

/** 读取命令文件并剥掉 YAML frontmatter，只注入正文指令。 */
async function loadCommandBody(file: string): Promise<string> {
  const raw = await readFile(join(COMMANDS_DIR, file), "utf8");
  if (!raw.startsWith("---\n")) return raw.trim();
  const end = raw.indexOf("\n---", 4);
  return (end === -1 ? raw : raw.slice(end + 4)).trim();
}

export default function registerPuaCommands(pi: ExtensionAPI): void {
  for (const spec of COMMANDS) {
    pi.registerCommand(spec.name, {
      description: `[pua] ${spec.description}`,
      handler: async (args: string) => {
        const body = await loadCommandBody(spec.file);
        const message = args.trim() ? `${body}\n\n## 本次任务参数\n\n${args.trim()}` : body;
        await pi.sendMessage(message);
      },
    });
  }
}
