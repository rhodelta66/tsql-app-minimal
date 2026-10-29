"""Validate id3.tsql.app access tokens. Identity comes only from the verified claims."""

import re

import jwt

# Tracy reads claim `role` as one string or an array of strings.
_ROLE_NAME = re.compile(r"^[A-Za-z0-9_. -]{1,128}$")

ISSUER = "https://id3.tsql.app"
JWKS_URL = "https://id3.tsql.app/.well-known/oauth2/certs"
# id3 and this host can differ by a second. A fresh token must not fail on that.
LEEWAY_SECONDS = 120

_jwk_client = jwt.PyJWKClient(JWKS_URL, cache_keys=True, lifespan=3600)


class AuthError(Exception):
    pass


def _signing_key(token):
    """Return the id3 RS256 key for this token.

    id3 publishes one signing key. Tokens sometimes omit `kid`, or send the
    same thumbprint in a different case. Both still name that one key.
    """
    try:
        return _jwk_client.get_signing_key_from_jwt(token)
    except jwt.PyJWKClientError:
        header = jwt.get_unverified_header(token)
        keys = [
            key
            for key in _jwk_client.get_signing_keys()
            if (key.public_key_use in ("sig", None))
        ]
        kid = header.get("kid")
        if kid:
            wanted = str(kid).lower()
            for key in keys:
                if key.key_id and str(key.key_id).lower() == wanted:
                    return key
        if not kid and len(keys) == 1:
            return keys[0]
        raise


def describe_rejected_bearer(header):
    """Safe text for the server log. Never includes the token or an email."""
    if not header:
        return "absent"
    if not header.lower().startswith("bearer "):
        return "scheme"
    token = header.split(" ", 1)[1].strip()
    if not token:
        return "empty"
    parts = token.split(".")
    bits = ["bearer", "segments=%d" % len(parts), "len=%d" % len(token)]
    try:
        header_claims = jwt.get_unverified_header(token)
        bits.append("alg=%s" % header_claims.get("alg"))
        bits.append("kid=%s" % ("yes" if header_claims.get("kid") else "no"))
        bits.append("typ=%s" % header_claims.get("typ"))
    except Exception as exc:
        bits.append("header=%s" % type(exc).__name__)
        return " ".join(bits)
    try:
        claims = jwt.decode(
            token,
            options={
                "verify_signature": False,
                "verify_aud": False,
                "verify_iss": False,
                "verify_exp": False,
                "verify_nbf": False,
                "verify_iat": False,
            },
        )
        bits.append("iss=%s" % claims.get("iss"))
        bits.append("claims=%s" % ",".join(sorted(claims)))
    except Exception as exc:
        bits.append("payload=%s" % type(exc).__name__)
    return " ".join(bits)


def roles_from_claims(claims):
    """Role names from the id3 claim Tracy reads.

    `role` may be one string or a list of strings. A string is a single name,
    not a comma-separated list. The card column ide_role is the list.
    """
    if not isinstance(claims, dict):
        return []
    raw = claims.get("role")
    if isinstance(raw, str):
        items = [raw]
    elif isinstance(raw, list):
        items = [item for item in raw if isinstance(item, str)]
    else:
        return []
    found = []
    seen = set()
    for item in items:
        name = item.strip()
        if not _ROLE_NAME.fullmatch(name):
            continue
        key = name.casefold()
        if key in seen:
            continue
        seen.add(key)
        found.append(name)
        if len(found) == 32:
            break
    return found


def verify_bearer(header):
    if not header or not header.lower().startswith("bearer "):
        raise AuthError("no bearer")
    token = header.split(" ", 1)[1].strip()
    if not token:
        raise AuthError("empty bearer")
    try:
        key = _signing_key(token)
        claims = jwt.decode(
            token,
            key.key,
            algorithms=["RS256"],
            issuer=ISSUER,
            leeway=LEEWAY_SECONDS,
            options={"verify_aud": False, "require": ["exp", "iss"]},
        )
    except AuthError:
        raise
    except Exception as exc:
        raise AuthError(type(exc).__name__) from exc
    if claims.get("iss") != ISSUER:
        raise AuthError("issuer")
    subject = claims.get("sub") or claims.get("uid")
    if not subject:
        raise AuthError("no subject")
    email = claims.get("email") or claims.get("preferred_username") or subject
    return {
        "sub": str(subject)[:256],
        "email": str(email)[:256],
        "roles": roles_from_claims(claims),
    }
