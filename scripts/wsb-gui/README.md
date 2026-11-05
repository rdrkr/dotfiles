# wsb-gui

Run and drive Windows GUI apps inside **Windows Sandbox**, so an agent (Claude Code) can click, type and
screenshot an app under test without touching the real mouse, keyboard or screen. It's the Windows
counterpart of the WSL + noVNC setup used for the Linux builds.

Needs Windows 11 24H2+ with Windows Sandbox enabled (it ships the `wsb` CLI).

## How it works

- `wsb-gui.ps1 -Start <profile>` starts a sandbox from `profiles/<profile>.ps1` and runs `wsb connect`. That
  opens the Windows Sandbox window, which creates the user session GUI work needs. **Minimize the window**:
  rendering, `SendInput` clicks, posted clicks, keys and screenshots all keep working while it is minimized
  (verified 2026-10-19). The host cursor never moves.
- `wsb exec` returns no output, so results go through the read-write folder `%LOCALAPPDATA%\wsb-gui\work`,
  mapped as `C:\work`. `-Start` copies `tools/` there.
- `wsb-gui.ps1 -Do <drive.ps1 args>` runs `tools/drive.ps1` in the sandbox user session and prints its result.
  One round-trip takes about 2.5 s.

```powershell
$g = "$HOME\dotfiles\scripts\wsb-gui\wsb-gui.ps1"
& $g -Start mf-side-by-side -ProfileArgs @{ Dev = '<build>\mf-dev'; Fix = '<build>\mf-fix'; Job = '<path>\test.mjf'; JobName = 'Test' }
& $g -Do -Action launch -Text 'C:\mf\dev\MAGNET_Field.exe'
& $g -Do -Action list   -ExeLike 'C:\mf\dev\'
& $g -Do -Action click  -ExeLike 'C:\mf\dev\' -Title 'Warning' -X 1250 -Y 1180
& $g -Do -Action shot   -ExeLike 'C:\mf\dev\' -Out 'C:\work\shots\dev-1.png'   # = %LOCALAPPDATA%\wsb-gui\work\shots
& $g -Do -Action shot -Screen -Out 'C:\work\shots\screen.png'
& $g -Exec 'cmd /c dir C:\mfdata > C:\work\out\dir.txt'
& $g -Stop                                                                   # disposable: nothing survives
```

`drive.ps1` actions: `list`, `shot`, `click`, `dclick`, `pclick` (posted; `-Text bm` adds `BM_CLICK`),
`keys` (SendKeys syntax, so `+ ^ % ~` need braces), `wheel`, `move`, `place`, `corner`, `launch`
(`-ArgList`), `cursor`.

## Profiles

- `mf-side-by-side`: two MAGNET Field (MF Classic) builds, `C:\mf\dev` and `C:\mf\fix`, each with its own data
  root `C:\mfdata\<b>` and an optional test job. Setup takes seconds, because the mapped folders copy fast.

## Gotchas

- `wsb exec -r ExistingLogin` fails with `0x80070520` until `wsb connect` has run.
- The sandbox has no Store apps (no Notepad, no Paint).
- The sandbox image already ships the VC++ 14.x runtime. `logon.ps1` only installs the redist when it is missing
  (the quiet install takes about 4 min).
- MF Classic sizes its windows to the screen: 2501x1290 in the sandbox vs 1810x1071 on the host. Don't resize
  them; it only half-repaints. Scale host-recorded coordinates instead: x×2501/1810, y×1290/1071, except the
  90 px top bar, which keeps its height.
- Both MF copies are full-screen on top of each other. `pclick`/`click` with `-ExeLike` and `-Title` still pick
  the right one, since `click` raises its window first.
- A trailing backslash before a closing quote escapes it on the Windows command line. `wsb-gui.ps1` doubles
  it for you.
- Windows Sandbox runs one instance at a time.
