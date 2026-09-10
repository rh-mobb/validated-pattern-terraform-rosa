"""Purpose: Exercise subnet capacity opt-in through the real Make entry points.

What this is not: No provider or cluster is contacted; account/network calls are recorded.
Prerequisites: Python 3, Bash, Make, and Git; missing tools skip this suite.
Authoritative references: https://docs.python.org/3/library/unittest.html
"""

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NOTICE = (
    "Subnet tag capacity: requested, but network validation was skipped "
    "(no VPC id resolved) — check did not run"
)
# Deliberately synthetic arguments; recording stubs never contact a provider.
VPC = "vpc-fixture"
BASE = (
    'region = "us-east-1"\nzero_egress = false\nmulti_az = true\n'
    'control_plane_log_cloudwatch_enabled = false\n'
)


@unittest.skipUnless(
    all(shutil.which(tool) for tool in ("bash", "make", "git")),
    "Bash, Make, and Git are required for validation invocation tests",
)
class ValidationInvocationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        for name in (
            "Makefile", "Makefile.common", "Makefile.cluster", "scripts/common.sh",
            "scripts/validate/prereqs.sh", "scripts/utils/check-cluster.sh",
        ):
            destination = self.root / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, destination)
        self.cluster = self.root / "clusters/probe"
        self.cluster.mkdir(parents=True)
        (self.root / "terraform").mkdir()
        (self.root / "bin").mkdir()
        self.executable("scripts/validate/account.sh", "#!/bin/sh\nexit 0\n")
        self.executable(
            "scripts/validate/byo-network.sh",
            "#!/bin/sh\nprintf '%s\\0' \"$@\" > \"$ARGV_FILE\"\n"
            'exit "${VALIDATOR_STUB_EXIT:-0}"\n',
        )
        self.executable(
            "bin/terraform",
            '#!/bin/sh\n[ "$*" = "output -raw vpc_id" ] || exit 91\n'
            'printf "%s\\n" "$TF_OUTPUT"\n',
        )
        for name in ("aws", "oc", "ocm", "rosa", "curl", "wget"):
            self.executable("bin/" + name, "#!/bin/sh\nexit 92\n")
        self.env = {
            "PATH": str(self.root / "bin") + os.pathsep + os.environ["PATH"],
            "LANG": "C.UTF-8", "ARGV_FILE": str(self.root / "argv.nul"),
            "TF_OUTPUT": VPC, "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_CONFIG_NOSYSTEM": "1",
        }

    def executable(self, name, body):
        path = self.root / name
        path.write_text(body)
        path.chmod(0o755)

    def configure(self, content, initialized=True):
        tfvars = self.cluster / "terraform.tfvars"
        tfvars.unlink(missing_ok=True)
        if content is not None:
            tfvars.write_text(content)
        sentinel = self.cluster / ".terraform/terraform.tfstate"
        sentinel.unlink(missing_ok=True)
        if initialized:
            sentinel.parent.mkdir(exist_ok=True)
            # Empty fixture sentinel, never a real state body or Terraform invocation.
            sentinel.touch()

    def invoke(self, target):
        record = self.root / "argv.nul"
        record.unlink(missing_ok=True)
        result = subprocess.run(
            ["make", "--no-print-directory", "cluster.probe." + target],
            cwd=self.root, env=self.env, capture_output=True, timeout=30, check=False,
        )
        argv = record.read_bytes().split(b"\0")[:-1] if record.exists() else None
        return result, [arg.decode() for arg in argv] if argv is not None else None

    def test_opt_in_argv_through_both_entry_points(self):
        cases = {
            "missing_file": (None, False),
            "missing_key": ("", False),
            "bare_true": ("check_subnet_tag_capacity = true\n", True),
            "quoted_true": ('check_subnet_tag_capacity = "true"\n', True),
            "false": ("check_subnet_tag_capacity = false\n", False),
            "junk": ('check_subnet_tag_capacity = "junk"\n', False),
            "misspelled_key": ("check_subnet_tags_capacity = true\n", False),
        }
        records = []
        for name, (value, enabled) in cases.items():
            for target in ("validate", "validate-network"):
                with self.subTest(case=name, target=target):
                    content = None if value is None else (
                        BASE + 'network_type = "existing"\n'
                        + 'existing_vpc_id = "' + VPC + '"\n' + value
                    )
                    self.configure(content)
                    result, argv = self.invoke(target)
                    self.assertEqual(result.returncode, 0, result.stderr.decode())
                    self.assertIsNotNone(argv)
                    self.assertEqual(argv.count("--check-subnet-tag-capacity"), int(enabled))
                    self.assertNotIn(NOTICE.encode(), result.stdout + result.stderr)
                    records.append({"case": name, "target": target, "argv": argv, "exit_code": 0})
        # Optional receipt destination is for local test evidence, never live inputs.
        if os.environ.get("SUBNET_ARGV_RECEIPT"):
            Path(os.environ["SUBNET_ARGV_RECEIPT"]).write_text(json.dumps(records, indent=2) + "\n")

    def test_shared_args_reach_terraform_managed_branch(self):
        self.configure(BASE + "check_subnet_tag_capacity = true\n")
        result, argv = self.invoke("validate")
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(argv[-2:], ["--vpc-id", VPC])
        self.assertIn("--check-subnet-tag-capacity", argv)

    def test_requested_but_unresolved_is_explicit_and_does_not_fail(self):
        for initialized, output in ((False, ""), (True, ""), (True, "null")):
            for target in ("validate", "validate-network"):
                with self.subTest(initialized=initialized, output=output, target=target):
                    # For full validate, the reported defect includes an ignored BYO id.
                    ignored_id = 'existing_vpc_id = "' + VPC + '"\n' if target == "validate" else ""
                    self.configure(BASE + ignored_id + "check_subnet_tag_capacity = true\n", initialized)
                    self.env["TF_OUTPUT"] = output
                    result, argv = self.invoke(target)
                    self.assertEqual(result.returncode, 0, result.stderr.decode())
                    self.assertIsNone(argv)
                    self.assertEqual((result.stdout + result.stderr).count(NOTICE.encode()), 1)

    def test_disabled_skips_have_no_new_notice(self):
        for key in ("", "check_subnet_tag_capacity = false\n", "check_subnet_tags_capacity = true\n"):
            for target in ("validate", "validate-network"):
                with self.subTest(key=key, target=target):
                    self.configure(BASE + key, initialized=False)
                    result, argv = self.invoke(target)
                    self.assertEqual(result.returncode, 0, result.stderr.decode())
                    self.assertIsNone(argv)
                    self.assertNotIn(NOTICE.encode(), result.stdout + result.stderr)

    def test_network_failure_propagates_to_make(self):
        self.configure(BASE + 'network_type = "existing"\nexisting_vpc_id = "' + VPC
                       + '"\ncheck_subnet_tag_capacity = true\n')
        self.env["VALIDATOR_STUB_EXIT"] = "1"
        for target in ("validate", "validate-network"):
            with self.subTest(target=target):
                result, argv = self.invoke(target)
                self.assertIn("--check-subnet-tag-capacity", argv)
                self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
