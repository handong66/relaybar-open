#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build-manual/tests"
OUTPUT_BIN="$BUILD_DIR/storage_auth_smoke_tests"
SDK_PATH="${SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk}"
DEFAULT_SWIFTC="/Library/Developer/CommandLineTools/usr/bin/swiftc"
if [[ -x "$DEFAULT_SWIFTC" ]]; then
  SWIFTC_BIN="${SWIFTC:-$DEFAULT_SWIFTC}"
else
  SWIFTC_BIN="${SWIFTC:-swiftc}"
fi

mkdir -p "$BUILD_DIR"

"$SWIFTC_BIN" \
  -sdk "$SDK_PATH" \
  "$ROOT_DIR/tests/StorageAndAuthSmokeTests.swift" \
  "$ROOT_DIR/RelayBar/Localization.swift" \
  "$ROOT_DIR/RelayBar/Models/OAuthTokens.swift" \
  "$ROOT_DIR/RelayBar/Models/ProviderSummaryState.swift" \
  "$ROOT_DIR/RelayBar/Models/TokenAccount.swift" \
  "$ROOT_DIR/RelayBar/Models/AntigravityAccount.swift" \
  "$ROOT_DIR/RelayBar/Models/AccountPanelState.swift" \
  "$ROOT_DIR/RelayBar/Models/UsageModels.swift" \
  "$ROOT_DIR/RelayBar/Services/AccountBuilder.swift" \
  "$ROOT_DIR/RelayBar/Services/CodexPaths.swift" \
  "$ROOT_DIR/RelayBar/Services/AntigravityPaths.swift" \
  "$ROOT_DIR/RelayBar/Services/AccountPoolRepository.swift" \
  "$ROOT_DIR/RelayBar/Services/AntigravityAccountRepository.swift" \
  "$ROOT_DIR/RelayBar/Services/DirectoryMonitor.swift" \
  "$ROOT_DIR/RelayBar/Services/AntigravityAccountStore.swift" \
  "$ROOT_DIR/RelayBar/Services/AntigravitySQLite.swift" \
  "$ROOT_DIR/RelayBar/Services/AntigravityProtobuf.swift" \
  "$ROOT_DIR/RelayBar/Services/OAuthManager.swift" \
  "$ROOT_DIR/RelayBar/Services/AntigravityOAuthManager.swift" \
  "$ROOT_DIR/RelayBar/Services/AntigravitySwitcher.swift" \
  "$ROOT_DIR/RelayBar/Services/AntigravityAccountImporter.swift" \
  "$ROOT_DIR/RelayBar/Services/AppIdentityMigration.swift" \
  "$ROOT_DIR/RelayBar/Services/AntigravityOAuthConfig.swift" \
  "$ROOT_DIR/RelayBar/Services/CredentialTransferService.swift" \
  "$ROOT_DIR/RelayBar/Services/CodexAuthResolver.swift" \
  "$ROOT_DIR/RelayBar/Services/CodexLocalUsageService.swift" \
  -o "$OUTPUT_BIN"

"$OUTPUT_BIN"
