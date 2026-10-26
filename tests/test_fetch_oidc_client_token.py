"""Regression tests for custody and exact-audience behavior.

Purpose: Prove that the helper writes owner-only tokens and never emits bearer
material through its diagnostic failures.
What this is not: These tests do not contact an issuer or validate a JWT
signature.
Prerequisites: Python's standard library and the companion helper source.
Authoritative references:
- https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-client-creds-grant-flow
- https://learn.microsoft.com/en-us/entra/identity-platform/access-token-claims-reference
"""

import base64
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

MODULE_PATH = (
    Path(__file__).parents[1] / "scripts" / "utils" / "fetch_oidc_client_token.py"
)
SPEC = importlib.util.spec_from_file_location("fetch_oidc_client_token", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


def segment(value):
    raw = json.dumps(value, separators=(",", ":")).encode()
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


class Response(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *_args):
        self.close()


class TokenHelperTest(unittest.TestCase):
    @unittest.skipUnless(
        os.name == "posix", "requires POSIX permissions and link semantics"
    )
    def test_acquire_and_write_never_prints_bearer(self):
        # The synthetic compact JWT is decoded only; signature verification is
        # deliberately left to the cluster authenticator.
        token = f"{segment({'alg': 'none'})}.{segment({'aud': 'expected', 'sub': 'subject'})}.signature"
        response = Response(
            json.dumps({"access_token": token, "expires_in": 60}).encode()
        )

        with mock.patch.object(MODULE.urllib.request, "urlopen", return_value=response):
            actual, claims, expires = MODULE.acquire(
                "https://issuer.example.invalid/token",
                "expected/.default",
                "client",
                "secret",
                1,
            )

        self.assertEqual(actual, token)
        self.assertEqual(claims["aud"], "expected")
        self.assertEqual(expires, 60)

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "token"
            MODULE.write_secret(path, actual)
            self.assertEqual(path.read_text().strip(), token)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    @unittest.skipUnless(
        os.name == "posix", "requires POSIX permissions and link semantics"
    )
    def test_existing_output_and_symlinks_are_not_replaced(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original = root / "original"
            original.write_text("other job")
            original.chmod(0o644)
            for name, target in [("link", original), ("dangling", root / "absent")]:
                (root / name).symlink_to(target)
            for path in [original, root / "link", root / "dangling"]:
                with self.assertRaises(FileExistsError):
                    MODULE.write_secret(path, "fictional bearer")
            self.assertEqual(original.read_text(), "other job")
            self.assertEqual(original.stat().st_mode & 0o777, 0o644)
            self.assertTrue((root / "link").is_symlink())
            self.assertTrue((root / "dangling").is_symlink())
            self.assertFalse((root / "absent").exists())
            self.assertEqual(len(list(root.iterdir())), 3)

    @unittest.skipUnless(
        os.name == "posix", "requires POSIX permissions and link semantics"
    )
    def test_competing_publication_is_refused_atomically(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "token"
            link = MODULE.os.link

            def competitor(source, destination, **kwargs):
                Path(destination).write_text("second job wins")
                return link(source, destination, **kwargs)

            with mock.patch.object(MODULE.os, "link", side_effect=competitor):
                with self.assertRaises(FileExistsError):
                    MODULE.write_secret(path, "first job bearer")
            self.assertEqual(path.read_text(), "second job wins")
            self.assertEqual(list(Path(directory).iterdir()), [path])

    @unittest.skipUnless(
        os.name == "posix", "requires POSIX permissions and link semantics"
    )
    def test_mode_is_private_before_first_write(self):
        with tempfile.TemporaryDirectory() as directory:
            original = MODULE.os.fdopen

            def inspect(fd, *args, **kwargs):
                self.assertEqual(MODULE.os.fstat(fd).st_mode & 0o777, 0o600)
                self.assertEqual(MODULE.os.fstat(fd).st_size, 0)
                return original(fd, *args, **kwargs)

            with mock.patch.object(MODULE.os, "fdopen", side_effect=inspect):
                MODULE.write_secret(Path(directory) / "token", "fictional bearer")

    def test_exact_audience(self):
        # A URI prefix is part of aud. Similar-looking values must not match.
        self.assertTrue(MODULE.audience_matches("api://value", "api://value"))
        self.assertFalse(MODULE.audience_matches("api://value", "value"))
        self.assertTrue(MODULE.audience_matches(["one", "two"], "two"))

    def test_http_error_does_not_include_body(self):
        # IdP error bodies are untrusted secret-bearing input. The helper may
        # retain the status code, but never the body or a bearer substring.
        error = MODULE.urllib.error.HTTPError(
            "https://issuer.example.invalid/token",
            401,
            "unauthorized",
            {},
            io.BytesIO(b"access_token=secret-bearer"),
        )
        with mock.patch.object(MODULE.urllib.request, "urlopen", side_effect=error):
            with self.assertRaisesRegex(RuntimeError, r"HTTP 401") as caught:
                MODULE.acquire(
                    "https://issuer.example.invalid/token",
                    "scope",
                    "client",
                    "secret",
                    1,
                )
        self.assertNotIn("secret-bearer", str(caught.exception))

    def test_untrusted_diagnostic_fields_are_not_returned_for_output(self):
        token = f"{segment({'alg': 'none'})}.{segment({'aud': 'expected', 'secret-bearer': 'value'})}.signature"
        response = Response(
            json.dumps({"access_token": token, "expires_in": "secret-bearer"}).encode()
        )
        with mock.patch.object(MODULE.urllib.request, "urlopen", return_value=response):
            _actual, claims, expires = MODULE.acquire(
                "https://issuer.example.invalid/token",
                "expected/.default",
                "client",
                "secret",
                1,
            )
        self.assertIsNone(expires)
        emitted_names = sorted(
            name for name in claims if name in MODULE.ALLOWED_CLAIM_NAMES
        )
        self.assertEqual(emitted_names, ["aud"])

    def test_transport_error_does_not_echo_reason(self):
        # A resolver, proxy, or fixture can supply arbitrary reason text. Keep
        # that text out of the diagnostic channel just like an HTTP body.
        error = MODULE.urllib.error.URLError("secret-bearer")
        with mock.patch.object(MODULE.urllib.request, "urlopen", side_effect=error):
            with self.assertRaisesRegex(
                RuntimeError, r"^token endpoint request failed$"
            ) as caught:
                MODULE.acquire(
                    "https://issuer.example.invalid/token",
                    "scope",
                    "client",
                    "secret",
                    1,
                )
        self.assertNotIn("secret-bearer", str(caught.exception))

    def test_timeout_must_be_positive(self):
        self.assertEqual(MODULE.positive_float("1.5"), 1.5)
        with self.assertRaisesRegex(
            MODULE.argparse.ArgumentTypeError, "greater than zero"
        ):
            MODULE.positive_float("0")


if __name__ == "__main__":
    unittest.main()
