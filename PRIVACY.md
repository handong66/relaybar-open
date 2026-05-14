# Privacy

RelayBar is a local macOS menu bar utility. It does not run a RelayBar cloud service and does not intentionally upload your credential export files to any RelayBar server.

## Local Data

RelayBar reads and writes local files to provide account switching, usage monitoring, and credential migration:

- `~/.codex/token_pool.json`
- `~/.codex/auth.json`
- `~/.codex/antigravity_pool.json`
- `~/Library/Application Support/Antigravity/User/globalStorage/storage.json`
- `~/Library/Application Support/Antigravity/User/globalStorage/state.vscdb`
- `~/.config/relaybar/antigravity-oauth.json` when you choose file-based Antigravity OAuth configuration
- macOS Keychain item `com.relaybar.antigravity-oauth` / `google-client` when you save Antigravity OAuth configuration through OAuth Setup

These files and Keychain items may contain access tokens, refresh tokens, ID tokens, account IDs, email addresses, device state, quota snapshots, and local usage summaries.

## Network Requests

RelayBar contacts OpenAI/ChatGPT/Codex-related endpoints for Codex OAuth and usage refresh. It contacts Google/Antigravity-related endpoints when you import or refresh Antigravity account data, refresh model quota, or use your own Google OAuth client for direct Antigravity OAuth.

The public release requires a user-provided Antigravity Google OAuth client for direct Antigravity add-account or reauthorization flows. The default Antigravity flow is to sign in through the official Antigravity app first, then import the current local login into RelayBar.

## Credential Export

Credential export files are plaintext JSON. They are intended for user-controlled migration between your own Macs.

Do not upload exported credential files to public repositories, public cloud links, issue trackers, pull requests, logs, or chat rooms. Delete temporary copies after importing them on the target Mac.

## No Cloud Sync

RelayBar does not include cloud synchronization. If you move credentials between machines, that transfer is controlled by you.
