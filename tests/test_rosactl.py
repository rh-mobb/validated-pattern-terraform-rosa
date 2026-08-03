#!/usr/bin/env python3
"""Unit tests for bin/rosactl (stdlib unittest)."""

from __future__ import annotations

import importlib.machinery
import importlib.util
import os
import sys
import tempfile
import unittest
from pathlib import Path


def load_rosactl():
    root = Path(__file__).resolve().parent.parent
    path = root / "bin" / "rosactl"
    loader = importlib.machinery.SourceFileLoader("rosactl", str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    sys.modules[loader.name] = mod
    loader.exec_module(mod)
    return mod


class TestRosactl(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.r = load_rosactl()

    def test_format_duration(self):
        self.assertEqual(self.r.format_duration(5), "5s")
        self.assertEqual(self.r.format_duration(65), "1m 05s")
        self.assertEqual(self.r.format_duration(3661), "1h 01m 01s")

    def test_truncate_for_terminal(self):
        long = "x" * 200
        out = self.r.truncate_for_terminal(long, columns=40)
        self.assertLessEqual(len(out), 40)
        self.assertTrue(out.endswith("..."))

    def test_iter_process_lines_handles_cr(self):
        import io

        # Simulate Terraform rewriting a progress line with \r then a final \n
        data = io.BytesIO(b"partial\rfinal line\nnext\n")
        lines = list(self.r.iter_process_lines(data))
        self.assertEqual(lines, ["partial", "final line", "next"])

    def test_is_robot_mode_flag(self):
        self.assertTrue(self.r.is_robot_mode(True))

    def test_is_robot_mode_ci(self):
        old = os.environ.get("CI")
        os.environ["CI"] = "true"
        try:
            self.assertTrue(self.r.is_robot_mode(False))
        finally:
            if old is None:
                del os.environ["CI"]
            else:
                os.environ["CI"] = old

    def test_steps_up_includes_bootstrap(self):
        root = Path("/tmp/fake-root")
        steps = self.r.steps_for(root, "up", "public", no_bootstrap=False)
        names = [s.name for s in steps]
        self.assertEqual(
            names,
            [
                "Terraform Init",
                "Terraform Plan",
                "Terraform Apply",
                "Ensure tunnel",
                "Bootstrap GitOps",
            ],
        )

    def test_steps_up_no_bootstrap(self):
        root = Path("/tmp/fake-root")
        steps = self.r.steps_for(root, "up", "public", no_bootstrap=True)
        names = [s.name for s in steps]
        self.assertEqual(names, ["Terraform Init", "Terraform Plan", "Terraform Apply"])

    def test_steps_plan(self):
        steps = self.r.steps_for(Path("/tmp"), "plan", "public")
        self.assertEqual([s.name for s in steps], ["Terraform Init", "Terraform Plan"])

    def test_log_paths(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "clusters" / "public").mkdir(parents=True)
            log_file, latest = self.r.log_paths(root, "public", "plan")
            self.assertTrue(str(log_file).endswith("-plan.log"))
            self.assertEqual(latest.name, "latest.log")
            self.assertTrue(log_file.parent.is_dir())

    def test_require_cluster_missing(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "clusters").mkdir()
            with self.assertRaises(SystemExit) as ctx:
                self.r.require_cluster(root, "nope")
            self.assertIn("does not exist", str(ctx.exception))

    def test_help_exits_zero(self):
        root = Path(__file__).resolve().parent.parent
        import subprocess

        proc = subprocess.run(
            [str(root / "bin" / "rosactl"), "--help"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 0)
        self.assertIn("cluster", proc.stdout)

    def test_no_args_prints_help(self):
        root = Path(__file__).resolve().parent.parent
        import subprocess

        proc = subprocess.run(
            [str(root / "bin" / "rosactl")],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 0)
        self.assertIn("usage: rosactl", proc.stdout)

    def test_cluster_without_verb_prints_help(self):
        root = Path(__file__).resolve().parent.parent
        import subprocess

        proc = subprocess.run(
            [str(root / "bin" / "rosactl"), "cluster"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 0)
        self.assertIn("usage: rosactl cluster", proc.stdout)

    def test_verb_help_is_specific(self):
        root = Path(__file__).resolve().parent.parent
        import subprocess

        proc = subprocess.run(
            [str(root / "bin" / "rosactl"), "cluster", "up", "--help"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 0)
        self.assertIn("usage: rosactl cluster up", proc.stdout)
        self.assertIn("--no-bootstrap", proc.stdout)
        self.assertIn("GitOps", proc.stdout)

    def test_robot_flag_after_verb_parses(self):
        """Flags after the verb work (cobra-like), same as before the verb."""
        with self.assertRaises(SystemExit) as ctx:
            self.r.main(["cluster", "plan", "nope-cluster", "--robot"])
        self.assertIn("does not exist", str(ctx.exception))

    def test_destroy_help_has_yes(self):
        root = Path(__file__).resolve().parent.parent
        import subprocess

        proc = subprocess.run(
            [str(root / "bin" / "rosactl"), "cluster", "destroy", "--help"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 0)
        self.assertIn("--yes", proc.stdout)

    def test_destroy_robot_requires_yes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "clusters" / "public").mkdir(parents=True)
            old = os.environ.get("ROSACTL_ROOT")
            os.environ["ROSACTL_ROOT"] = str(root)
            try:
                code = self.r.main(["--robot", "cluster", "destroy", "public"])
            finally:
                if old is None:
                    del os.environ["ROSACTL_ROOT"]
                else:
                    os.environ["ROSACTL_ROOT"] = old
        self.assertEqual(code, 1)


if __name__ == "__main__":
    unittest.main()
