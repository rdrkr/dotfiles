# wsb-gui

Run and drive Windows GUI apps inside **Windows Sandbox**, so an agent (e.g. Claude Code) can click, type and
screenshot an app under test without touching the real mouse, keyboard or screen. It's the Windows
counterpart of a WSL + noVNC setup.

Needs Windows 11 24H2+ with Windows Sandbox enabled (it ships the `wsb` CLI).

## How it works

- `wsb-gui.ps1 -Start <profile>` starts a sandbox from `profiles/<profile>.ps1` and runs `wsb connect`. That
  opens the Windows Sandbox window, which creates the user session GUI work needs. **Minimize the window**:
  rendering, `SendInput` clicks, posted clicks, keys and screenshots all keep working while it is minimized.
  The host cursor never moves.
- `wsb exec` returns no output, so results go through the read-write folder `%LOCALAPPDATA%\wsb-gui\work`,
  mapped as `C:\work`. `-Start` copies `tools/` there.
- `wsb-gui.ps1 -Do <drive.ps1 args>` runs `tools/drive.ps1` in the sandbox user session and prints its result.
  One round-trip takes about 2.5 s.

```powershell
$g = "$HOME\dotfiles\scripts\wsb-gui\wsb-gui.ps1"
& $g -Start compare -ProfileArgs @{ Builds = @{ dev = 'D:\build\dev'; fix = 'D:\build\fix' } }
& $g -Do -Action launch -Text 'C:\app\dev\MyApp.exe'
& $g -Do -Action list   -ExeLike 'C:\app\dev\'
& $g -Do -Action click  -ExeLike 'C:\app\dev\' -Title 'Warning' -X 1250 -Y 1180
& $g -Do -Action shot   -ExeLike 'C:\app\dev\' -Out 'C:\work\shots\dev-1.png'   # = %LOCALAPPDATA%\wsb-gui\work\shots
& $g -Do -Action shot -Screen -Out 'C:\work\shots\screen.png'
& $g -Exec 'cmd /c dir C:\app > C:\work\out\dir.txt'
& $g -Stop                                                                   # disposable: nothing survives
```

`drive.ps1` actions: `list`, `shot`, `click`, `dclick`, `pclick` (posted; `-Text bm` adds `BM_CLICK`),
`keys` (SendKeys syntax, so `+ ^ % ~` need braces), `wheel`, `move`, `place`, `count` (pixels in a colour
range, to recognise a screen by an icon), `launch` (`-ArgList`), `cursor`.

## Profiles

- `compare`: any number of named builds of one app, `C:\app\<name>`, to compare them (e.g. `dev` vs `fix`).
  Copying happens in seconds. It also takes:
  - `-Setup <host .ps1>`: an app-specific hook, run once per build in the sandbox with
    `-Name -AppDir -DataDir`. Keep hooks with the app or in `%LOCALAPPDATA%\wsb-gui\setups`, not here.
  - `-Data <folder>`: test data, mapped read-only as `C:\host\data`.

## Gotchas

- `wsb exec -r ExistingLogin` fails with `0x80070520` until `wsb connect` has run.
- The sandbox has no Store apps (no Notepad, no Paint).
- The sandbox image already ships a VC++ 14.x runtime. The redist is only installed when it is missing (the
  quiet install takes about 4 min).
- Apps that size themselves to the screen get the sandbox's resolution, not the host's. Coordinates recorded
  on the host then need scaling, and right-anchored toolbars shift instead of scaling. `place` can resize
  windows, but some apps repaint badly afterwards.
- A trailing backslash before a closing quote escapes it on the Windows command line. `wsb-gui.ps1` doubles
  it for you.
- Windows Sandbox runs one instance at a time.
