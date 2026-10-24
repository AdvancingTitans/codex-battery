# Security

The current release is maintained on a best-effort basis. Use the latest version.

The app asks the installed Codex CLI to read rate limits. The CLI owns authentication and its network requests. The app does not copy credentials, scrape browser cookies or send telemetry to an app-owned server.

Do not post secrets in public issues. Prefer GitHub's private vulnerability reporting when available on the repository Security tab. If it is unavailable, open a minimal issue requesting a private reporting channel without disclosing the vulnerability or credentials.

Release archives have SHA-256 checksums and ad-hoc signatures, not Apple Developer ID notarization. A checksum verifies that you have the published bytes; it does not replace review of the source or Apple's security checks.
