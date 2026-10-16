# 270135 Native Tip Implementation Plan

Goal: deliver the approved experimental native tip mode plus a silent rollback config.
Architecture: use existing Config/Patcher and Resigner; no Swift production changes or new dependencies.

- [ ] Extend Tests/main.swift: seed actual 270135 offsets, apply keeptip from pristine and silent, verify restored CBZ and STR XZR, repeat apply, rollback to silent and verify restored STR X0. Missing config must fail first.
- [ ] Add config-4.1.15.55-keeptip.json and config-4.1.15.55-silent-restore.json with expected-byte guards. Run synthetic suite using work/swiftc-local.
- [ ] Copy installed app into a separate staging directory, patch using current CLI and explicit config, strictly verify signature and all three patch points.
- [ ] Quit installed instances, check build remains 270135, atomically retain current app and deploy staged app. Verify launch; restore prior app if startup fails.
- [ ] Package source/config/tool with validation boundaries and rollback instructions. Ask user to verify private chat with a disposable test message.
