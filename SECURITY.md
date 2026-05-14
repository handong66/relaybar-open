# Security Policy

RelayBar handles local authentication material for Codex and Antigravity accounts. Treat the repository, local data files, and exported credential files accordingly.

## Supported Versions

Security fixes target the latest public release and the current `main` branch.

## Reporting a Vulnerability

Please report vulnerabilities privately through GitHub Security Advisories when available. If you must open a public issue, keep it minimal and do not include tokens, exported credentials, database files, screenshots with account secrets, or exploit details.

Do not paste any of the following into public issues, pull requests, logs, screenshots, or chat rooms:

- `~/.codex/token_pool.json`
- `~/.codex/auth.json`
- `~/.codex/antigravity_pool.json`
- `~/.config/relaybar/antigravity-oauth.json`
- `RelayBar-Credentials-*.json`
- `storage.json` or `state.vscdb` from Antigravity global storage
- access tokens, refresh tokens, ID tokens, OAuth client secrets, cookies, private keys, or database files

## Secret Handling

RelayBar stores account tokens locally because Codex and Antigravity read local auth state. The app does not provide RelayBar cloud sync.

Credential export files are plaintext JSON and may contain access tokens, refresh tokens, ID tokens, device state, quota snapshots, and account identifiers. Store them like passwords and delete temporary transfer copies after import.

The public source and release packages do not provide an Antigravity Google OAuth client secret. Users who need direct Antigravity OAuth must provide their own local configuration through OAuth Setup, environment variables, or `~/.config/relaybar/antigravity-oauth.json`.

OAuth Setup stores the user-provided Antigravity OAuth client in macOS Keychain under service `com.relaybar.antigravity-oauth` and account `google-client`.

## Public Repository Gate

Before publishing code or release assets, maintainers should run:

```sh
scripts/run_foundation_tests.sh
gitleaks detect --no-git --redact --source .
gitleaks detect --redact
```

Any real secret finding blocks publication. Placeholder strings such as `YOUR_CLIENT_SECRET` in example files are allowed only when they are obviously non-real placeholders.
