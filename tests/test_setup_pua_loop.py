#!/usr/bin/env python3
"""setup-pua-loop.sh 冒烟测试（离线，HOME/cwd 双沙箱）。

③分类说明：该脚本是副作用脚本（写状态文件），但副作用全部可沙箱化——
HOME 重定向到 tmp、cwd 切到 tmp，因此写**真实行为测试**而非跳过。
钉死：--help、参数校验显性失败、状态文件命名（cwd md5 前 8 位）、
frontmatter 字段（max_iterations/promise/verify YAML 引号）、legacy 副本、
history jsonl 初始化。
跑法：python3 -m pytest tests -q
"""
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "setup-pua-loop.sh"


class LoopSetupCase(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="pua-setup-test-"))
        self.home = self.tmp / "home"
        self.work = self.tmp / "work"
        self.home.mkdir()
        self.work.mkdir()

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_script(self, *args):
        env = dict(os.environ)
        env["HOME"] = str(self.home)
        return subprocess.run(
            ["bash", str(SCRIPT), *args],
            cwd=str(self.work), env=env,
            capture_output=True, text=True, timeout=60,
        )

    @property
    def state_path(self):
        h = hashlib.md5(str(self.work).encode()).hexdigest()[:8]
        return self.home / ".claude" / "pua" / f"loop-{h}.md"

    def frontmatter(self):
        text = self.state_path.read_text(encoding="utf-8")
        m = re.match(r"\A---\r?\n(.*?)\r?\n---\r?\n", text, re.S)
        self.assertIsNotNone(m, "状态文件必须有 YAML frontmatter")
        fm = {}
        for line in m.group(1).splitlines():
            if ":" in line:
                k, v = line.split(":", 1)
                fm[k.strip()] = v.strip().strip('"')  # 值可能带 YAML 引号
        return fm, text


class TestArgValidation(LoopSetupCase):
    """所有参数错误必须显性 exit 1，不静默继续。"""

    def test_help_exits_0(self):
        r = self.run_script("--help")
        self.assertEqual(r.returncode, 0)
        self.assertIn("USAGE", r.stdout)
        self.assertIn("--verify", r.stdout)
        self.assertIn("GATE PROTOCOL", r.stdout)
        self.assertFalse((self.home / ".claude" / "pua").exists())  # --help 不落状态

    def test_no_prompt_exits_1(self):
        r = self.run_script()
        self.assertEqual(r.returncode, 1)
        self.assertIn("No prompt", r.stderr)
        self.assertFalse(self.state_path.exists())

    def test_max_iterations_missing_value(self):
        r = self.run_script("fix bugs", "--max-iterations")
        self.assertEqual(r.returncode, 1)
        self.assertIn("requires a number", r.stderr)

    def test_max_iterations_non_numeric(self):
        r = self.run_script("fix bugs", "--max-iterations", "abc")
        self.assertEqual(r.returncode, 1)
        self.assertIn("positive integer", r.stderr)

    def test_verify_missing_value(self):
        r = self.run_script("fix bugs", "--verify")
        self.assertEqual(r.returncode, 1)
        self.assertIn("--verify requires a command", r.stderr)

    def test_completion_promise_missing_value(self):
        r = self.run_script("fix bugs", "--completion-promise")
        self.assertEqual(r.returncode, 1)
        self.assertIn("requires a text", r.stderr)


class TestStateFile(LoopSetupCase):
    """正常路径：状态文件 + legacy 副本 + history jsonl。"""

    def test_minimal_run_defaults(self):
        r = self.run_script("fix all tests")
        self.assertEqual(r.returncode, 0, r.stderr)
        fm, text = self.frontmatter()
        self.assertEqual(fm["active"], "true")
        self.assertEqual(fm["iteration"], "1")
        self.assertEqual(fm["max_iterations"], "10")  # 安全默认上限
        self.assertEqual(fm["completion_promise"], "null")
        self.assertEqual(fm["verify_command"], "null")
        self.assertIn("fix all tests", text)  # prompt 进入状态文件
        self.assertIn("此 loop 默认上限 10 轮", text)  # 无 promise → 上限协议
        self.assertIn("不接受自报完成", text)  # 无 verify → 无 Oracle 协议
        self.assertEqual(fm["started_cwd"], str(self.work))

    def test_state_filename_is_cwd_md5_prefix8(self):
        self.run_script("work")
        h = hashlib.md5(str(self.work).encode()).hexdigest()[:8]
        self.assertTrue(self.state_path.name.endswith(f"loop-{h}.md"),
                        self.state_path.name)

    def test_full_run_with_oracle(self):
        r = self.run_script(
            "fix all tests", "--verify", "npm test",
            "--completion-promise", "ALL TESTS PASS",
            "--max-iterations", "3",
        )
        self.assertEqual(r.returncode, 0, r.stderr)
        fm, text = self.frontmatter()
        self.assertEqual(fm["max_iterations"], "3")
        # YAML 字符串值带引号写入（防短语空格/特殊字符破坏 frontmatter）
        self.assertIn('completion_promise: "ALL TESTS PASS"', text)
        self.assertIn('verify_command: "npm test"', text)
        self.assertIn("<promise>ALL TESTS PASS</promise>", text)
        self.assertIn("npm test", text)  # Oracle 命令写入协议
        self.assertIn("Oracle active", r.stdout)  # 摘要明示门控已激活

    def test_legacy_copy_identical(self):
        self.run_script("work")
        legacy = self.work / ".claude" / "pua-loop.local.md"
        self.assertTrue(legacy.is_file(), "legacy 副本必须存在（向后兼容）")
        self.assertEqual(legacy.read_text(encoding="utf-8"),
                         self.state_path.read_text(encoding="utf-8"))

    def test_history_jsonl_initialized(self):
        self.run_script("work", "--verify", "cargo test")
        hist = self.work / ".claude" / "pua-loop-history.jsonl"
        self.assertTrue(hist.is_file())
        lines = hist.read_text(encoding="utf-8").splitlines()
        self.assertEqual(len(lines), 1)
        rec = json.loads(lines[0])
        self.assertEqual(rec["iteration"], 0)
        self.assertEqual(rec["status"], "init")
        self.assertEqual(rec["verify_command"], "cargo test")

    def test_global_history_has_state_path(self):
        self.run_script("work")
        gh = self.home / ".claude" / "pua" / "loop-history.jsonl"
        self.assertTrue(gh.is_file())
        rec = json.loads(gh.read_text(encoding="utf-8").splitlines()[-1])
        self.assertEqual(rec["state_path"], str(self.state_path))

    def test_rerun_overwrites_state(self):
        self.run_script("first prompt")
        self.run_script("second prompt")
        fm, text = self.frontmatter()
        self.assertIn("second prompt", text)
        self.assertNotIn("first prompt", text)
        # history jsonl 是重新初始化而非追加（init 记录只有一条）
        hist = self.work / ".claude" / "pua-loop-history.jsonl"
        self.assertEqual(len(hist.read_text(encoding="utf-8").splitlines()), 1)

    def test_multi_word_prompt_joined(self):
        self.run_script("fix", "all", "the", "tests")
        _, text = self.frontmatter()
        self.assertIn("fix all the tests", text)

    def test_session_id_picked_from_env(self):
        env_backup = os.environ.get("CLAUDE_CODE_SESSION_ID")
        os.environ["CLAUDE_CODE_SESSION_ID"] = "sess-test-123"
        try:
            self.run_script("work")
        finally:
            if env_backup is None:
                os.environ.pop("CLAUDE_CODE_SESSION_ID", None)
            else:
                os.environ["CLAUDE_CODE_SESSION_ID"] = env_backup
        fm, _ = self.frontmatter()
        self.assertEqual(fm["session_id"], "sess-test-123")


if __name__ == "__main__":
    unittest.main()
