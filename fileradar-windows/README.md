# FileRadar for Windows

WinUI 3 / .NET 8 Explorer replacement matching the Mac FileRadar look system.

## Features (v1)

- Four looks: Modern, Elegant, Colourful, Minimal × Light / Dark / System
- Sidebar: Home, Search, Cleanup, Duplicates, Timeline, Recycle Bin + Places
- Home shelves, grid/list, inspector, dual-pane, staging trash, search

## Build

```powershell
cd fileradar-windows\FileRadar
dotnet restore
dotnet build -c Release -r win-x64
```

Runnable output (after publish):

```powershell
dotnet publish -c Release -r win-x64 --self-contained true -o ..\..\dist
```

## Version

`1.0.0-b1`
