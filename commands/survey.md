---
description: "PUA 调研问卷 — 7 部分交互式问卷收集用户反馈。/pua:survey。Triggers on: '/pua:survey', 'pua survey', '调研', '问卷', 'feedback survey'."
---

读取 `references/survey.md` 问卷文件，用 AskUserQuestion 逐部分交互式引导用户回答。每部分 2-4 个问题一组，用户回答后进入下一部分。回答完毕后汇总为 JSON 写入 `~/.pua/survey-response.json` 并上传到 `https://pua-skill.pages.dev/api/feedback`
