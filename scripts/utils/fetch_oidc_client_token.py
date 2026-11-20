#!/usr/bin/env python3
"""Fetch an OIDC client-credentials token without printing the bearer.

Purpose: Acquire one job-scoped OAuth client-credentials access token safely.
What this is not: This helper is not a JWT signature verifier, provider author,
or general-purpose response dumper.
Prerequisites: An HTTPS token endpoint, a dedicated confidential client in
OIDC_CLIENT_ID/OIDC_CLIENT_SECRET, an exact expected audience, and a private
output directory.
Authoritative references:
- https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-client-creds-grant-flow
- https://learn.microsoft.com/en-us/entra/identity-platform/scopes-oidc
- https://learn.microsoft.com/en-us/entra/identity-platform/access-token-claims-reference

The token is written atomically to a new mode-0600 file. Only allowlisted
metadata is written to stdout; HTTP response bodies are never included in
errors because they can repeat secrets or bearers.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
from pathlib import Path
import stat
import tempfile
import urllib.error
import urllib.parse
import urllib.request

# Claim names documented in Entra's access-token claims reference; only names,
# never values, may cross the output boundary. Unknown names are omitted rather
# than reflected so an issuer cannot use claim keys as an output channel.
# Ref: https://learn.microsoft.com/en-us/entra/identity-platform/access-token-claims-reference
ALLOWED_CLAIM_NAMES = frozenset(
    {
        "appid",
        "aud",
        "azp",
        "email",
        "exp",
        "groups",
        "iat",
        "iss",
        "nbf",
        "oid",
        "preferred_username",
        "roles",
        "scp",
        "sub",
        "tid",
        "upn",
        "ver",
    }
)


def positive_float(raw: str) -> float:
    """Reject timeout values that would make the network bound meaningless."""
    value = float(raw)
    if value <= 0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return value


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--token-url",
        required=True,
        help="HTTPS OAuth token endpoint; discovery is intentionally out of scope",
    )
    parser.add_argument(
        "--scope",
        required=True,
        help="OAuth scope such as <resource>/.default; this selects the token resource",
    )
    parser.add_argument(
        "--expected-audience",
        required=True,
        help="Exact aud member required in the returned JWT; URI prefixes are significant",
    )
    parser.add_argument(
        "--output",
        required=True,
        type=Path,
        help="New owner-only token file; existing paths are refused",
    )
    parser.add_argument(
        "--timeout",
        type=positive_float,
        # 20 s comfortably covers a token-endpoint round trip while failing a
        # hung proxy quickly; this is operator-declared, not a vendor value.
        default=20.0,
        help="Positive token-endpoint timeout in seconds (default: 20)",
    )
    return parser.parse_args()


def decode_segment(segment: str) -> dict[str, object]:
    # JWT uses unpadded base64url. Decoding claim names/audience is a local
    # sanity check only; the Kubernetes authenticator verifies the signature.
    padding = "=" * (-len(segment) % 4)
    raw = base64.urlsafe_b64decode((segment + padding).encode("ascii"))
    value = json.loads(raw)
    if not isinstance(value, dict):
        raise ValueError("JWT payload is not an object")
    return value


def jwt_claims(token: str) -> dict[str, object]:
    parts = token.split(".")
    if len(parts) != 3:
        raise ValueError("access_token is not a compact JWT")
    return decode_segment(parts[1])


def audience_matches(actual: object, expected: str) -> bool:
    # Accept the two JWT aud shapes but retain exact string membership. This
    # prevents the api://<identifier> versus bare-identifier silent mismatch.
    # Ref: https://learn.microsoft.com/en-us/entra/identity-platform/access-token-claims-reference
    if isinstance(actual, str):
        return actual == expected
    if isinstance(actual, list):
        return all(isinstance(item, str) for item in actual) and expected in actual
    return False


def acquire(
    token_url: str,
    scope: str,
    client_id: str,
    client_secret: str,
    timeout: float,
) -> tuple[str, dict[str, object], object]:
    # Refuse plaintext endpoints before any client secret enters a request.
    if not token_url.startswith("https://"):
        raise ValueError("token URL must use HTTPS")
    # Client credentials belong in the TLS-protected form body, never argv or
    # query parameters. Ref: https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-client-creds-grant-flow
    body = urllib.parse.urlencode(
        {
            "grant_type": "client_credentials",
            "client_id": client_id,
            "client_secret": client_secret,
            "scope": scope,
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        token_url,
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as exc:
        # Do not include reason phrases or response bodies: an IdP can echo
        # request material, and a success-shaped body contains the bearer.
        raise RuntimeError(f"token endpoint returned HTTP {exc.code}") from None
    except urllib.error.URLError:
        # Transport error strings are untrusted diagnostics and can include
        # request details. Preserve only the failure class.
        raise RuntimeError("token endpoint request failed") from None

    if not isinstance(payload, dict) or not isinstance(
        payload.get("access_token"), str
    ):
        raise ValueError("token endpoint response omitted access_token")
    token = payload["access_token"]
    expires_raw = payload.get("expires_in")
    # Keep response diagnostics allowlisted: arbitrary strings from an issuer
    # must never become an output channel.
    expires_in = (
        expires_raw
        if isinstance(expires_raw, int) and not isinstance(expires_raw, bool)
        else None
    )
    return token, jwt_claims(token), expires_in


def write_secret(path: Path, value: str) -> None:
    # Build privately, then publish with a hard link: link creation refuses an
    # existing destination atomically, including a dangling symlink or a path
    # created by another job after our temporary file was opened. Same-directory
    # placement keeps both names on one filesystem; unsupported links fail closed.
    # Ref: https://docs.python.org/3/library/os.html#os.link
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        os.fchmod(fd, stat.S_IRUSR | stat.S_IWUSR)
        stream = os.fdopen(fd, "w", encoding="utf-8")
        fd = None  # stream now owns the descriptor
        with stream:
            stream.write(value)
            stream.write("\n")
        os.link(temporary, path, follow_symlinks=False)
    finally:
        if fd is not None:
            os.close(fd)
        os.unlink(temporary)


def main() -> int:
    args = parse_args()
    client_id = os.environ.get("OIDC_CLIENT_ID")
    client_secret = os.environ.get("OIDC_CLIENT_SECRET")
    # Environment input keeps credential values out of the process argument
    # vector; callers must still disable shell tracing and environment dumps.
    if not client_id or not client_secret:
        raise SystemExit("OIDC_CLIENT_ID and OIDC_CLIENT_SECRET must be set")

    try:
        token, claims, expires_in = acquire(
            args.token_url,
            args.scope,
            client_id,
            client_secret,
            args.timeout,
        )
        # The scope requested from Entra does not guarantee the spelling of
        # aud. Decode and byte-match before writing a token a pipeline may use.
        if not audience_matches(claims.get("aud"), args.expected_audience):
            raise ValueError(
                "returned JWT audience did not exactly match the expected audience"
            )
        write_secret(args.output, token)
    finally:
        # Drop the local references as soon as practical. The caller remains
        # responsible for unsetting its environment and deleting the file.
        client_secret = None

    # Only reviewed non-secret names and numeric expiry metadata may cross the
    # output boundary. Unknown claim names are omitted rather than reflected.
    claim_names = ",".join(
        sorted(name for name in claims if name in ALLOWED_CLAIM_NAMES)
    )
    expiry = str(expires_in) if expires_in is not None else "unknown"
    print(f"token written securely; expires_in={expiry}; claim_names={claim_names}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
