"""Purpose: Prove exclusive credential creation, safe refusal and bounded cleanup.
What this is not: The fictional bearer and mock oc do not contact an issuer or cluster.
Prerequisites: Python 3 and the companion scripts; tests skip when their POSIX/Bash/Python or GNU utility dependencies are unavailable.
Authoritative references: https://docs.python.org/3/library/os.html#os.open
"""

import concurrent.futures
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import signal
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).parents[1] / "examples/pipeline-identities/service-account"
BEARER = "fictional-custody-fixture"


@unittest.skipUnless(
    os.name == "posix" and hasattr(os, "O_NOFOLLOW"),
    "requires POSIX owner-only modes and no-follow file opens",
)
@unittest.skipUnless(
    shutil.which("bash") and shutil.which("python3"),
    "requires Bash and python3 on PATH for the shell helper",
)
class CustodyTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        oc = self.bin / "oc"
        oc.write_text(r"""#!/usr/bin/env python3
import json, os, pathlib, sys, time
args = sys.argv[1:]
path = pathlib.Path(next(x.split("=", 1)[1] for x in args if x.startswith("--kubeconfig=")))
config = json.loads(path.read_text())
assert config["users"][0]["user"]["token"] == "fictional-custody-fixture"
assert path.stat().st_mode & 0o777 == 0o600
assert path.parent.stat().st_mode & 0o777 == 0o700
assert "fictional-custody-fixture" not in " ".join(args)
with open(os.environ["MOCK_LOG"], "a") as stream:
    stream.write(json.dumps({"path": str(path), "args": args}) + "\n")
if "whoami" in args:
    print(os.environ.get("MOCK_SUBJECT", "system:serviceaccount:fixture:deployer"))
elif "apply" in args:
    if os.environ.get("MOCK_WAIT"):
        time.sleep(60)
    sys.exit(int(os.environ.get("MOCK_FAIL_APPLY", "0")))
""")
        oc.chmod(0o755)
        self.path = self.root / "kubeconfig"
        self.env = {
            **os.environ,
            "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
            "PIPELINE_TOKEN": BEARER,
            "PIPELINE_API_SERVER": "https://cluster.example.invalid:6443",
            "PIPELINE_NAMESPACE": "fixture",
            "PIPELINE_SERVICE_ACCOUNT": "deployer",
            "KUBECONFIG_PATH": str(self.path),
            "PIPELINE_TOKEN_EXPIRY": "",
            "MOCK_LOG": str(self.root / "calls.jsonl"),
            "MANIFEST_DIR": "fictional-manifests",
            "DEPLOYMENT_NAME": "fixture",
            "PIPELINE_CLEANUP_RECEIPT": str(self.root / "cleanup"),
        }

    def require_gnu(self, command):
        binary = shutil.which(command)
        if not binary:
            self.skipTest(f"requires GNU {command} on PATH")
        try:
            result = subprocess.run(
                [binary, "--version"],
                capture_output=True,
                text=True,
                timeout=5,
                check=True,
            )
        except (OSError, subprocess.SubprocessError):
            self.skipTest(f"requires GNU {command}; version probe failed")
        if "GNU coreutils" not in result.stdout:
            self.skipTest(f"requires GNU {command}, not a different implementation")

    def require_wrapper_dependencies(self):
        self.require_gnu("timeout")
        for command in ("dirname", "mktemp", "rm", "rmdir"):
            if not shutil.which(command):
                self.skipTest(f"wrapper requires {command} on PATH")
        if Path("/tmp").is_symlink():
            self.skipTest(
                "wrapper requires a non-symlink /tmp, as in the Linux CI image"
            )

    def run_helper(self):
        r = subprocess.run(
            ["bash", str(ROOT / "mint-kubeconfig.sh")],
            env=self.env,
            capture_output=True,
            text=True,
        )
        self.assertNotIn(BEARER, r.stdout + r.stderr)
        return r

    def test_new_output_is_owner_only_and_json_safe(self):
        self.env["PIPELINE_API_SERVER"] += "/quoted'path"
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(
            json.loads(self.path.read_text())["clusters"][0]["cluster"]["server"],
            self.env["PIPELINE_API_SERVER"],
        )

    def test_existing_file_is_refused_without_changing_content_or_mode(self):
        self.path.write_text("previous job")
        self.path.chmod(0o644)
        self.assertNotEqual(self.run_helper().returncode, 0)
        self.assertEqual(self.path.read_text(), "previous job")
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o644)
        self.assertFalse(Path(self.env["MOCK_LOG"]).exists())

    def test_symlink_is_refused_without_touching_target(self):
        target = self.root / "other"
        target.write_text("other job")
        target.chmod(0o644)
        self.path.symlink_to(target)
        self.assertNotEqual(self.run_helper().returncode, 0)
        self.assertTrue(self.path.is_symlink())
        self.assertEqual(target.read_text(), "other job")
        self.assertEqual(target.stat().st_mode & 0o777, 0o644)

    def test_dangling_symlink_is_refused(self):
        self.path.symlink_to(self.root / "absent")
        self.assertNotEqual(self.run_helper().returncode, 0)
        self.assertTrue(self.path.is_symlink())
        self.assertFalse((self.root / "absent").exists())

    def test_symlink_parent_is_refused(self):
        link = self.root / "linked"
        link.symlink_to(self.root, target_is_directory=True)
        self.env["KUBECONFIG_PATH"] = str(link / "token")
        self.assertNotEqual(self.run_helper().returncode, 0)
        self.assertFalse((self.root / "token").exists())

    def test_shared_parent_is_refused(self):
        self.root.chmod(0o755)
        self.assertNotEqual(self.run_helper().returncode, 0)
        self.assertFalse(self.path.exists())

    def test_identity_failure_removes_only_new_output(self):
        self.env["MOCK_SUBJECT"] = "different-subject"
        retained = self.root / "retained"
        retained.write_text("keep")
        self.assertNotEqual(self.run_helper().returncode, 0)
        self.assertFalse(self.path.exists())
        self.assertEqual(retained.read_text(), "keep")

    def test_expiry_is_advisory_or_unobserved_and_imminent_expiry_refuses(self):
        self.require_gnu("date")
        self.assertIn("expiry unobserved", self.run_helper().stderr)
        self.path.unlink()
        self.env["PIPELINE_TOKEN_EXPIRY"] = (
            datetime.now(timezone.utc) + timedelta(seconds=700)
        ).isoformat()
        self.assertIn("advisory margin only", self.run_helper().stdout)
        self.path.unlink()
        self.env["PIPELINE_TOKEN_EXPIRY"] = (
            datetime.now(timezone.utc) + timedelta(seconds=60)
        ).isoformat()
        self.assertNotEqual(self.run_helper().returncode, 0)
        self.assertFalse(self.path.exists())

    def assert_cleanup(self):
        self.assertEqual(
            Path(self.env["PIPELINE_CLEANUP_RECEIPT"]).read_text(), "complete\n"
        )
        records = [
            json.loads(x) for x in Path(self.env["MOCK_LOG"]).read_text().splitlines()
        ]
        self.assertEqual(len({x["path"] for x in records}), 1)
        self.assertFalse(Path(records[0]["path"]).parent.exists())

    def test_wrapper_cleans_after_success(self):
        self.require_wrapper_dependencies()
        r = subprocess.run(
            ["bash", str(ROOT / "run-deployment.sh")], env=self.env, capture_output=True
        )
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assert_cleanup()

    def test_wrapper_cleans_and_preserves_deploy_failure(self):
        self.require_wrapper_dependencies()
        self.env["MOCK_FAIL_APPLY"] = "7"
        r = subprocess.run(
            ["bash", str(ROOT / "run-deployment.sh")], env=self.env, capture_output=True
        )
        self.assertEqual(r.returncode, 7, r.stderr)
        self.assert_cleanup()

    def test_wrapper_cleans_on_catchable_termination(self):
        self.require_wrapper_dependencies()
        self.env["MOCK_WAIT"] = "1"
        p = subprocess.Popen(
            ["bash", str(ROOT / "run-deployment.sh")],
            env=self.env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )
        try:
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                log = Path(self.env["MOCK_LOG"])
                if log.exists() and any(
                    '"apply"' in line for line in log.read_text().splitlines()
                ):
                    break
                time.sleep(0.02)
            else:
                self.fail("mock apply never started")
            os.killpg(p.pid, signal.SIGTERM)
            p.communicate(timeout=5)
            self.assertNotEqual(p.returncode, 0)
            self.assert_cleanup()
        finally:
            if p.poll() is None:
                os.killpg(p.pid, signal.SIGKILL)
            p.communicate()


if __name__ == "__main__":
    unittest.main()
