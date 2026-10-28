# FileRadar for Windows

WinUI 3 / .NET 8 Explorer replacement matching the Mac FileRadar look system.

## Features (v1)

- Four looks: Modern, Elegant, Colourful, Minimal × Light / Dark / System
- Sidebar: Home, Search, Cleanup, Duplicates, Timeline, Recycle Bin + Places
- Home shelves, grid/list, inspector, dual-pane, staging trash, search

## Run (portable exe)

Double-click:

```
c:\Users\saran\Desktop\FileRadar Windows\dist\FileRadar.exe
```

Or unzip `FileRadarWindows-1.0.0-b1-20261028.zip` and run `FileRadar\FileRadar.exe`.

**WinAppSDK / runtime deps must sit beside the exe.** This is an unpackaged self-contained publish (`WindowsPackageType=None`, `WindowsAppSDKSelfContained=true`). Keep the whole `dist\` folder together — do not copy `FileRadar.exe` alone.

True single-file (`PublishSingleFile=true`) **publishes but crashes at launch** on WinUI 3 / Windows App SDK (CLR unhandled exception). Use the portable folder layout instead.

## Build / publish

```powershell
cd fileradar-windows\FileRadar
dotnet restore
dotnet build -c Release -r win-x64 -p:Platform=x64
dotnet publish -c Release -r win-x64 -p:Platform=x64 --self-contained true -p:PublishSingleFile=false -o ..\..\dist
```

## Version

`1.0.0-b1`
