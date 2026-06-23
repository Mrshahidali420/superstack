---
name: ss-secure
description: Use before shipping anything that touches authentication, user input, data, secrets, or money. Runs an OWASP Top 10 + STRIDE review and a secret scan over the diff, with a concrete exploit scenario and confidence score per finding.
---

# Secure

The sixth phase. A gate, not an afterthought — mandatory for anything touching auth,
user input, persisted data, or money.

## Steps

1. **OWASP Top 10 pass** over the diff: injection, broken auth, broken access control,
   SSRF, security misconfig, vulnerable dependencies, etc.
2. **STRIDE threat model:** Spoofing, Tampering, Repudiation, Information disclosure,
   Denial of service, Elevation of privilege — which apply to what changed?
3. **Secret scan:** no API keys, tokens, passwords, or private keys in the code or diff.
   Confirm secrets come from env/secret manager and are validated at startup.
4. **Boundary checks:** all external input validated; parameterized queries (never string
   concatenation); least privilege; errors don't leak sensitive detail.
5. **Per finding,** write a concrete exploit scenario and a confidence score (0–10).
   Report only findings at **≥ 7** to keep signal high.

## Gate

No CRITICAL findings and no secrets in the diff. Then `/ss-ship`.

## Lineage

gstack `/cso` (OWASP + STRIDE, exploit-per-finding, confidence gate).
