# Contributing to PUA Skill

感谢你对 PUA Skill 的关注！以下是提交 Issue 和 PR 的规范。

## Issue 提交规范

### 1. 必须归类

每个 Issue 必须使用模板并选择正确的类型：

| 类型 | 前缀 | 用途 |
|------|------|------|
| Bug | `bug:` | 功能异常、命令不触发、hook 报错 |
| Feature | `feat:` | 新功能、新味道、新平台支持 |
| Question | `question:` | 使用疑问（提问前请先查阅 [Guide](https://openpua.ai/guide.html)） |

不符合归类规范的 Issue 将被关闭并要求重新提交。

### 2. 关于 "PUA 话术是否有效" 的讨论

PUA Skill 的理论基础已在我们的研究博客中系统阐述：

**[Emotion/Persona Prompting 对 AI Agent 效果的系统性分析](https://openpua.ai/blog/emotion-persona-prompting.html)**

核心结论：
- PUA Skill 85-90% 的效果来自**结构化行为约束**（checklist、escalation protocol、验证步骤），而非情感修辞
- PUA 话术（"3.25"、"毕业"等）的真正作用是**注意力锚定和行为路由信号**，不是"激发 AI 的情感"
- 这一结论基于 20+ 篇顶会论文（ACL/EMNLP/ICML/IJCAI）的系统梳理

**以下类型的 Issue 不会被接受：**
- 仅凭 AI 工具（ChatGPT/Claude/Gemini 等）分析本项目代码后得出"PUA 话术对 LLM 无效"的结论来否定项目价值。我们已经在上述博客中对这个问题做了比任何 AI 摘要更深入的分析，包括 EmotionPrompt/Persona Prompting 的局限性、Anthropic Persona Vectors 的机制差异、以及 PUA 话术作为 routing signal 的量化分解
- 没有提供**新的实验数据或论文引用**、仅靠观点否定的 Issue

**欢迎的讨论方式：**
- 带有自己的 A/B 实验数据的效果质疑（如 [PR #82](https://github.com/tanweai/pua/pull/82) 的 SM skill 就是很好的范例）
- 引用我们博客中未覆盖的新论文
- 基于具体场景的改进建议

### 3. 社区行为准则

**以下行为将导致自动化处理：**
- 对项目或维护者的攻击、辱骂、人身攻击 → Issue 将被自动关闭，账号将被永久拉黑
- 垃圾信息、广告、无关内容 → 自动关闭
- 重复提交已关闭的 Issue → 自动关闭

我们使用自动化工具监控 Issue 内容。恶意行为零容忍。

## PR 提交规范

### 基本要求

- 每个 PR 解决一个问题，不要混合多个无关改动
- PR 标题使用 conventional commit 格式：`fix:` / `feat:` / `chore:` / `docs:`
- 如果改了核心 SKILL.md，请说明改动的理由和预期效果
- 如果改了多个平台的文件（cursor/kiro/vscode/codex），请确保内容同步
- PR body 必须包含：Summary（改了什么）+ Test plan（怎么验证的）

### AI Agent 提交的 PR

我们欢迎 AI agent（Claude Code、Codex CLI、Cursor 等）提交的 PR。但**纯代码不够——必须附带测试证据**：

**必须提供：**
- [ ] **测试记录**：截图、命令输出、或日志，证明改动在本地跑通了
- [ ] **改动前后对比**：如果是 bug fix，展示修复前的报错和修复后的正常输出
- [ ] **影响分析**：改了 A 文件，B 和 C 有没有受影响？如果涉及多个平台，是否全部同步？
- [ ] **Agent 身份声明**：在 PR body 中注明使用了哪个 AI agent（如 "Generated with Claude Code"），这不是歧视——是为了让 reviewer 知道需要额外检查哪些 AI 常见问题（如幻觉、过度重构、引入未使用的依赖）

**不接受的 AI PR：**
- 只有代码改动，没有任何测试证据
- AI 自动生成的"改进建议"类 PR（如自动 refactor、自动加注释），除非有明确的 issue 指向
- 改了核心 SKILL.md 但没有 A/B 效果对比数据

**优秀范例：** [PR #82](https://github.com/tanweai/pua/pull/82)（SM skill）和 [PR #102](https://github.com/tanweai/pua/pull/102)（hooks + security）都附带了完整的测试清单。

### 代码质量要求

- **不引入新的安全漏洞**：OWASP Top 10、命令注入、XSS、明文密钥等。我们有自动化安全 hook 检查
- **不破坏现有功能**：修了 A 不能坏 B。PR 中如果涉及 hooks/shell 脚本，请用 `bash -n` 验证语法
- **保持向后兼容**：如果改了 config.json 的字段结构，需要兼容旧版本 config
- **文件域隔离**：不同 PR 不应该改同一个文件。如果发现冲突，先沟通再提交
- **API 改动需编译验证**：仅当改了 `landing/functions/` 下的 TypeScript API 时，需确保编译通过。Skill 文件（Markdown/Shell）不需要编译

### Commit Message 规范

```
<type>(<scope>): <subject>

<body>

<footer>
```

| type | 用途 |
|------|------|
| `fix` | Bug 修复 |
| `feat` | 新功能 |
| `chore` | 构建/工具/版本/配置 |
| `docs` | 文档 |
| `refactor` | 重构（不改行为） |
| `test` | 测试 |
| `style` | 格式调整 |

scope 可选：`skill`、`hooks`、`landing`、`agents`、`commands`、`security`

### Review 流程

1. 提交 PR → 自动化检查（语法、安全）
2. 维护者 review → 可能要求补充测试证据或修改
3. 通过 review → 合并到 main
4. 涉及 landing page 的改动会在合并后自动部署到 openpua.ai

### 首次贡献者

如果这是你第一次向 PUA Skill 贡献代码，欢迎！建议从以下入手：
- 标记了 `good first issue` 的 Issue
- 文档翻译（中/英/日三语同步）
- 新的味道包（参考 `references/flavors.md` 的格式）
- 新平台支持（参考现有的 cursor/kiro/vscode 目录结构）

## 联系方式

- Telegram: https://t.me/+wBWh6h-h1RhiZTI1
- Discord: https://discord.gg/EcyB3FzJND
- Email: minwei.wang@tanweai.com
