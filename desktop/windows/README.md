# Connect Sports Pro — Windows desktop

This directory contains the first Windows desktop shell for Connect Sports Pro.

## Architecture

- Tauri 2 desktop shell
- Production UI: https://connectsportspro.com/login/
- No Tauri IPC capabilities are exposed to the remote web application
- Windows WebView2 renderer
- NSIS installer output (.exe)

The web application remains the source of truth. The desktop client does not fork or duplicate CSP business logic.

## Local build on Windows

Prerequisites:

1. Node.js 22+
2. Rust stable
3. Microsoft C++ Build Tools with Desktop development with C++
4. WebView2 runtime

Then:

```powershell
cd desktop/windows
npm install
npm run build
```

Outputs:

- application binary: `src-tauri/target/release/csp-windows.exe`
- installer: `src-tauri/target/release/bundle/nsis/*-setup.exe`

## CI build

GitHub Actions workflow `.github/workflows/build-csp-windows.yml` builds the x64 Windows executable and NSIS installer and uploads both as one artifact.

## Current scope

Version 0.1.0 is an online desktop shell. Offline scoreboard, native notifications, device registration, auto-update and code signing are intentionally deferred to later phases.
