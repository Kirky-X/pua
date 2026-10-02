// Landing copy for the PUA Skill site (en / zh / ja).
// Flavor labels mirror hooks/flavors.json: 14 corporate methodologies plus the
// "ding" workplace-discipline flavor. The Microsoft entry carries the real
// performance-review vocabulary from skills/pua/references/methodology-microsoft.md
// (Connects, Impact Descriptor, SLITE/LITE, PIP, GVSA).

export type Locale = "en" | "zh" | "ja";

export type CopyKey =
  | "navHome"
  | "navContribute"
  | "navAdmin"
  | "tagline"
  | "homeIntro"
  | "homeCta"
  | "flavorsHeading"
  | "contributeTitle"
  | "contributeIntro"
  | "sanitizeNote"
  | "chooseFileLabel"
  | "wechatIdLabel"
  | "wechatIdPlaceholder"
  | "consentLabel"
  | "uploadButton"
  | "uploading"
  | "uploadSuccess"
  | "uploadFailed"
  | "rateLimited"
  | "loginRequired"
  | "consentRequired"
  | "chooseFileFirst"
  | "loginSuccess"
  | "loginInvalidState"
  | "logoutDone"
  | "adminTitle"
  | "adminLoginPrompt"
  | "adminLoginButton"
  | "adminForbidden"
  | "adminLoadFailed"
  | "statTotalInstalls"
  | "statActiveInstalls"
  | "statWindowDays"
  | "tableFlavor"
  | "tablePlatform"
  | "tableVersion"
  | "tableInstalls"
  | "footerNote";

type CopyTable = Record<CopyKey, string>;

const en: CopyTable = {
  navHome: "Home",
  navContribute: "Contribute",
  navAdmin: "Admin",
  tagline: "14 corporate methodologies, one relentless review coach in your terminal.",
  homeIntro:
    "PUA Skill turns big-tech performance-review pressure into a feedback coach for coding agents: pick a flavor, ship evidence, close the loop. Contribute sanitized session transcripts to help tune the pressure curves.",
  homeCta: "Upload a sanitized session",
  flavorsHeading: "The flavors",
  contributeTitle: "Contribute a session",
  contributeIntro:
    "Upload the sanitized .jsonl transcript produced by the Stop hook. The file goes straight to the analytics bucket — no GitHub login needed.",
  sanitizeNote:
    "Paths, API keys, emails and IPs are redacted locally before upload; the server re-runs redaction as defense in depth.",
  chooseFileLabel: "Sanitized session file (.jsonl)",
  wechatIdLabel: "WeChat id (optional, only if you want credit)",
  wechatIdPlaceholder: "not-provided",
  consentLabel: "I confirm this transcript is sanitized and I consent to uploading it.",
  uploadButton: "Upload session",
  uploading: "Uploading…",
  uploadSuccess: "Upload accepted. Thank you!",
  uploadFailed: "Upload failed. Check the file and try again.",
  rateLimited: "Too many uploads from your network. Try again later.",
  loginRequired: "This upload requires GitHub login.",
  consentRequired: "Upload consent is required.",
  chooseFileFirst: "Choose a .jsonl file first.",
  loginSuccess: "GitHub login complete — you can upload now.",
  loginInvalidState: "Login could not be verified (bad state). Try again.",
  logoutDone: "Logged out.",
  adminTitle: "Heartbeat stats",
  adminLoginPrompt: "Admin access only. Sign in with GitHub to view install heartbeat stats.",
  adminLoginButton: "Sign in with GitHub",
  adminForbidden: "This account is not in the admin allowlist.",
  adminLoadFailed: "Could not load heartbeat stats.",
  statTotalInstalls: "Total installs",
  statActiveInstalls: "Active installs",
  statWindowDays: "window",
  tableFlavor: "Flavor",
  tablePlatform: "Platform",
  tableVersion: "Version",
  tableInstalls: "Installs",
  footerNote: "PUA Skill is open source. Telemetry is opt-in and anonymous.",
};

const zh: CopyTable = {
  navHome: "首页",
  navContribute: "贡献 session",
  navAdmin: "管理",
  tagline: "14 种大厂方法论，一个不肯放过你的终端教练。",
  homeIntro:
    "PUA Skill 把大厂绩效话术变成 coding agent 的反馈教练：选一个味道，拿证据，交闭环。上传脱敏后的 session 记录，帮我们调准压力曲线。",
  homeCta: "上传脱敏 session",
  flavorsHeading: "味道一览",
  contributeTitle: "贡献 session",
  contributeIntro:
    "上传 Stop hook 生成的脱敏 .jsonl 记录。文件直接进入分析桶，不需要 GitHub 登录。",
  sanitizeNote:
    "文件路径、API 密钥、邮箱和 IP 在本地已完成脱敏；服务端会再跑一遍脱敏，作为纵深防御。",
  chooseFileLabel: "脱敏 session 文件（.jsonl）",
  wechatIdLabel: "微信号（可选，仅用于署名）",
  wechatIdPlaceholder: "not-provided",
  consentLabel: "我确认该记录已脱敏，并同意上传。",
  uploadButton: "上传 session",
  uploading: "上传中…",
  uploadSuccess: "上传成功，感谢！",
  uploadFailed: "上传失败，请检查文件后重试。",
  rateLimited: "你的网络上传过于频繁，请稍后再试。",
  loginRequired: "该上传需要 GitHub 登录。",
  consentRequired: "必须先勾选上传同意。",
  chooseFileFirst: "请先选择 .jsonl 文件。",
  loginSuccess: "GitHub 登录完成，可以上传了。",
  loginInvalidState: "登录状态校验失败，请重试。",
  logoutDone: "已退出登录。",
  adminTitle: "心跳统计",
  adminLoginPrompt: "仅管理员可访问。请用 GitHub 登录查看安装心跳统计。",
  adminLoginButton: "使用 GitHub 登录",
  adminForbidden: "该账号不在管理员白名单中。",
  adminLoadFailed: "心跳统计加载失败。",
  statTotalInstalls: "累计安装",
  statActiveInstalls: "活跃安装",
  statWindowDays: "统计窗口",
  tableFlavor: "味道",
  tablePlatform: "平台",
  tableVersion: "版本",
  tableInstalls: "安装数",
  footerNote: "PUA Skill 是开源项目。遥测为自愿开启且完全匿名。",
};

const ja: CopyTable = {
  navHome: "ホーム",
  navContribute: "セッション提供",
  navAdmin: "管理",
  tagline: "14の企業メソドロジー、あなたのターミナルにいる鬼コーチ。",
  homeIntro:
    "PUA Skill は大企業の人事評価プレッシャーを、コーディングエージェント向けのフィードバックコーチに変えます。フレーバーを選び、証拠を出し、ループを閉じる。サニタイズ済みセッションの提供もお願いします。",
  homeCta: "サニタイズ済みセッションをアップロード",
  flavorsHeading: "フレーバー一覧",
  contributeTitle: "セッションを提供",
  contributeIntro:
    "Stop hook が生成したサニタイズ済み .jsonl をアップロードします。GitHub ログインは不要で、解析バケットへ直接保存されます。",
  sanitizeNote:
    "パス・API キー・メール・IP はローカルでマスク済み。サーバー側でも再度マスクします（多層防御）。",
  chooseFileLabel: "サニタイズ済みセッションファイル（.jsonl）",
  wechatIdLabel: "WeChat ID（任意、署名用）",
  wechatIdPlaceholder: "not-provided",
  consentLabel: "このセッションがマスク済みであり、アップロードに同意します。",
  uploadButton: "セッションをアップロード",
  uploading: "アップロード中…",
  uploadSuccess: "アップロード完了。ありがとうございます！",
  uploadFailed: "アップロードに失敗しました。ファイルを確認してください。",
  rateLimited: "アップロードが集中しています。後でお試しください。",
  loginRequired: "このアップロードには GitHub ログインが必要です。",
  consentRequired: "アップロードへの同意が必要です。",
  chooseFileFirst: "まず .jsonl ファイルを選んでください。",
  loginSuccess: "GitHub ログインが完了しました。アップロードできます。",
  loginInvalidState: "ログイン状態を検証できませんでした。もう一度お試しください。",
  logoutDone: "ログアウトしました。",
  adminTitle: "ハートビート統計",
  adminLoginPrompt: "管理者専用です。GitHub でログインしてインストール統計を表示してください。",
  adminLoginButton: "GitHub でログイン",
  adminForbidden: "このアカウントは管理者許可リストに含まれていません。",
  adminLoadFailed: "ハートビート統計を読み込めませんでした。",
  statTotalInstalls: "累計インストール",
  statActiveInstalls: "アクティブ",
  statWindowDays: "期間",
  tableFlavor: "フレーバー",
  tablePlatform: "プラットフォーム",
  tableVersion: "バージョン",
  tableInstalls: "インストール数",
  footerNote: "PUA Skill はオープンソースです。テレメトリはオプトインかつ匿名です。",
};

const DICTIONARIES: Readonly<Record<Locale, CopyTable>> = { en, zh, ja };

export const FLAVORS: ReadonlyArray<{
  id: string;
  icon: string;
  label: Readonly<Record<Locale, string>>;
}> = [
  {
    id: "alibaba",
    icon: "🟠",
    label: {
      en: "Alibaba — 底层逻辑, 抓手, closed loops, the 3.25",
      zh: "阿里 —— 底层逻辑、抓手、闭环、3.25",
      ja: "アリババ — 底层逻辑・抓手・3.25",
    },
  },
  {
    id: "bytedance",
    icon: "🟡",
    label: {
      en: "ByteDance — ROI, Always Day 1, candid clarity",
      zh: "字节 —— ROI、Always Day 1、坦诚清晰",
      ja: "ByteDance — ROI・Always Day 1・坦诚清晰",
    },
  },
  {
    id: "huawei",
    icon: "🔴",
    label: {
      en: "Huawei — military orders, self-criticism, evidence delivery",
      zh: "华为 —— 军令状、自我批判、证据化交账",
      ja: "華為 — 軍令状・自己批判・証拠納品",
    },
  },
  {
    id: "tencent",
    icon: "🟢",
    label: {
      en: "Tencent — horse racing, small fast steps, MVP",
      zh: "腾讯 —— 赛马机制、小步快跑、MVP",
      ja: "騰訊 — 賽馬機制・小歩快跑",
    },
  },
  {
    id: "baidu",
    icon: "⚫",
    label: {
      en: "Baidu — technical faith, simple & dependable, search first",
      zh: "百度 —— 技术信仰、简单可依赖、搜索先行",
      ja: "百度 — 技術信仰・簡単可依頼",
    },
  },
  {
    id: "pinduoduo",
    icon: "🟣",
    label: {
      en: "Pinduoduo — 本分, grinding for real, no shortcuts",
      zh: "拼多多 —— 本分、拼命不是拼凑",
      ja: "PDD — 本分・徹底執行",
    },
  },
  {
    id: "meituan",
    icon: "🔵",
    label: {
      en: "Meituan — do hard & right things, long-term patience",
      zh: "美团 —— 做难而正确的事、长期有耐心",
      ja: "美団 — 難而正確・長期耐心",
    },
  },
  {
    id: "jd",
    icon: "🟦",
    label: {
      en: "JD — first place only, zero tolerance on customer experience",
      zh: "京东 —— 只做第一、客户体验零容忍",
      ja: "京東 — 第一のみ・顧客体験ゼロ容認",
    },
  },
  {
    id: "xiaomi",
    icon: "🟧",
    label: {
      en: "Xiaomi — focus, excellence, reputation, speed",
      zh: "小米 —— 专注极致口碑快、和用户交朋友",
      ja: "小米 — 専注極致口碑快",
    },
  },
  {
    id: "netflix",
    icon: "🟤",
    label: {
      en: "Netflix — freedom & responsibility, the keeper test",
      zh: "Netflix —— 自由与责任、Keeper Test",
      ja: "Netflix — 自由と責任・Keeper Test",
    },
  },
  {
    id: "musk",
    icon: "⬛",
    label: {
      en: "Musk — extremely hardcore, the algorithm, ship or die",
      zh: "Musk —— 极度硬核、the algorithm、ship or die",
      ja: "Musk — 超ハードコア・the algorithm",
    },
  },
  {
    id: "jobs",
    icon: "⬜",
    label: {
      en: "Jobs — A players, real artists ship, taste at the intersection",
      zh: "Jobs —— A 级人才、real artists ship、品味",
      ja: "Jobs — Aプレイヤー・real artists ship",
    },
  },
  {
    id: "amazon",
    icon: "🔶",
    label: {
      en: "Amazon — customer obsession, bias for action, Day 1",
      zh: "Amazon —— 用户痴迷、Bias for Action、Day 1",
      ja: "Amazon — Customer Obsession・Day 1",
    },
  },
  {
    id: "microsoft",
    icon: "🪟",
    label: {
      en: "Microsoft — Connects entries, Impact Descriptor (Exceptional / Successful / SLITE / LITE), Three Circles of Impact, PIP and GVSA gates, two-year rehire clauses, AI fluency",
      zh: "微软（Microsoft）—— Connects 绩效叙事、Impact Descriptor（Exceptional / Successful / SLITE / LITE）、三圈影响力、PIP / GVSA 制度终局、two-year rehire、AI fluency",
      ja: "マイクロソフト（Microsoft）— Connects、Impact Descriptor（Exceptional / Successful / SLITE / LITE）、PIP / GVSA、AI fluency",
    },
  },
  {
    id: "ding",
    icon: "📌",
    label: {
      en: "Ding — workplace discipline flavor: 钉内闭环, 钉外验收, evidence chains",
      zh: "钉 —— 职场纪律味：钉内闭环、钉外验收、证据链",
      ja: "釘 — 職場規律フレーバー：証拠チェーン",
    },
  },
];

let currentLocale: Locale = "en";

export function detectLocale(): Locale {
  const languages = typeof navigator !== "undefined" ? navigator.languages ?? [navigator.language] : [];
  for (const language of languages) {
    if (language && language.toLowerCase().startsWith("zh")) {
      currentLocale = "zh";
      return currentLocale;
    }
    if (language && language.toLowerCase().startsWith("ja")) {
      currentLocale = "ja";
      return currentLocale;
    }
  }
  currentLocale = "en";
  return currentLocale;
}

export function setLocale(locale: Locale): void {
  currentLocale = locale;
}

export function currentLocaleName(): Locale {
  return currentLocale;
}

export function t(key: CopyKey): string {
  return DICTIONARIES[currentLocale][key];
}
