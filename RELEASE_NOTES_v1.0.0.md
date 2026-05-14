# RelayBar v1.0.0

This is the reset initial public release of RelayBar.

## Downloads

- `RelayBar-v1.0.0-macOS.dmg`
- `RelayBar-v1.0.0-macOS.zip`

Both packages contain `RelayBar.app`. The app is ad-hoc signed and not Apple-notarized. On first launch, macOS may require opening it from Finder with right click, then Open.

## Highlights

- Manage Codex and Antigravity account pools from one macOS menu bar app.
- View remaining quota, reset timing, and account state.
- Show local Codex usage for Today, Yesterday, and Last 30 Days.
- Import the current official Antigravity login and restore captured local login snapshots for account switching.
- Import and export selected Codex and Antigravity accounts through a single RelayBar credential file.
- Keep switching manual. RelayBar does not auto-switch accounts when quota is low.

## Antigravity OAuth

The public source and release packages do not provide an Antigravity Google OAuth client secret.

Recommended Antigravity flow:

1. Sign in to the target account in the official Antigravity app.
2. Open RelayBar and select the Antigravity tab.
3. Click `Import Current Login`.
4. Use RelayBar to switch between imported accounts.

Direct Antigravity OAuth through RelayBar requires your own Google OAuth client. Save it through OAuth Setup, environment variables, or `~/.config/relaybar/antigravity-oauth.json`.

## Privacy And Credentials

RelayBar stores account data locally. It does not run a RelayBar cloud service.

Credential export files are plaintext JSON and may contain access tokens, refresh tokens, ID tokens, account identifiers, device state, and quota snapshots. Treat them like password files and delete temporary transfer copies after import.

## Checksums

SHA-256:

```text
649255bcccbf9c77c90250ef09dab18bc14a46f6ad6a3982f2e936c3637694b2  RelayBar-v1.0.0-macOS.dmg
8eca57921fc806b412edc5924235a2d174a1f7e25c2cc9179f15ec60c8e80e0d  RelayBar-v1.0.0-macOS.zip
```

## Known Limitations

- RelayBar is not affiliated with or endorsed by OpenAI, Google, Codex, or Antigravity.
- Some quota and local state behavior depends on local files or unofficial/internal endpoints that may change.
- Codex may need to restart before it reads a newly written auth file.
- Antigravity switching modifies local `storage.json` and `state.vscdb`; RelayBar creates backups before writing.
