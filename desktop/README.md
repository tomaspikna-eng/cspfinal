# Connect Sports Pro — Windows desktop

This folder contains the Tauri 2 Windows desktop wrapper for Connect Sports Pro.

## Current architecture

The desktop application loads the production CSP frontend from:

https://connectsportspro.com

The Windows shell is separate from the production web deployment, so changes in this folder do not alter the Vercel frontend.

## Build locally on Windows

Requirements:

- Node.js 22+
- Rust stable
- Microsoft C++ Build Tools / Visual Studio Build Tools
- WebView2 runtime

Commands:

```powershell
cd desktop
npm install
npm run tauri build
```

The NSIS installer is generated under:

```
desktop\src-tauri\target\release\bundle\nsis\
```

## GitHub Actions

Run the workflow **Build CSP Windows EXE** or push changes to the `windows-desktop` branch.

The workflow uploads an artifact named:

`Connect-Sports-Pro-Windows`

containing the generated `*-setup.exe` installer.

## Security note

The remote CSP frontend is not granted Tauri native capabilities. Native APIs should only be added later through narrowly scoped capabilities.
