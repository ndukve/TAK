# Security Policy

## Supported Versions

Only the latest tagged release receives security fixes. Older tags are not backported.

| Version | Supported |
|---------|-----------|
| latest (`v1.0.7`) | ✅ |
| < v1.0.7 | ❌ |

## Reporting a Vulnerability

Please **do not** open a public GitHub issue for security vulnerabilities.

Use [GitHub Security Advisories](https://github.com/ndukve/TAK/security/advisories/new) to report privately — this keeps the report confidential until a fix ships.

Include, where possible:
- Affected component (admin API, admin UI, TAK Server containers, deployment scripts)
- Steps to reproduce
- Impact (what an attacker could actually do)

You should receive an acknowledgement within a few days. There's no fixed SLA — this is a small, self-hosted project — but reports are taken seriously and fixes are prioritized by severity.

## Scope

This repo covers the containerized deployment (`docker-compose.yml`, install/backup/restore scripts) and the custom admin panel (`admin/api`, `admin/ui`). It does not cover vulnerabilities in the upstream official TAK Server itself — report those to [tak.gov](https://tak.gov/).

## Notes for Reviewers

- Client onboarding uses mutual TLS; the admin panel is JWT-authenticated with role-based access (`superadmin`/`admin`/`readonly`/`field`).
- Uploads (packages, plugins, map sources) are extension-allowlisted, size-capped, and path-sanitized against traversal.
- The admin panel has been through a full internal security audit (auth, upload validation, path traversal, self-lockout guards, etc.) — see commit history for details.
