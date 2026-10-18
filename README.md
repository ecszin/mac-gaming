# MacGaming — Steam + CrossOver + NotProton + GPTK on macOS

A single script with an interactive menu that **installs, updates, verifies, restores and uninstalls** the stack for running Windows Steam games on Apple Silicon Macs:

- **[Steam](https://store.steampowered.com/)** — macOS client
- **[CrossOver](https://www.codeweavers.com/crossover)** — Windows compatibility layer
- **[NotProton](https://github.com/NotProtonNot/NotProton)** — enables Steam Play in the macOS Steam client, using CrossOver as a Compatibility Tool
- **[Game Porting Toolkit](https://developer.apple.com/games/game-porting-toolkit/)** (GPTK) — Apple's D3DMetal (DirectX 11/12 → Metal)

The script automates the manual process of copying GPTK's D3DMetal into the NotProton runner, the game prefixes and CrossOver.app, always backing up before overwriting anything.

> ⚠️ **Experimental project.** GPTK 4 is in beta and NotProton is at an early stage. Use at your own risk.

---

## Requirements

| Item | Minimum |
|---|---|
| Mac | Apple Silicon (M1 or later) |
| macOS | 27 recommended (GPTK 4) |
| RAM | 16 GB recommended |
| Account | Apple ID (free) to download the GPTK |

**Rosetta 2** and **Homebrew** are installed automatically if missing.

Tested on: MacBook Air M5 · macOS 27.0.1 · CrossOver 26.3 · GPTK 4.0 beta 3.

---

## Installation

```bash
curl -fsSL -o ~/Downloads/install-gaming-mac.sh \
  https://raw.githubusercontent.com/ecszin/mac-gaming/main/install-gaming-mac.sh
chmod +x ~/Downloads/install-gaming-mac.sh
~/Downloads/install-gaming-mac.sh
```

Or download it manually in your browser: [install-gaming-mac.sh](https://github.com/ecszin/mac-gaming/blob/main/install-gaming-mac.sh) → **Download raw file** button → save it to `~/Downloads` and run the last two commands above.

On first run the script:

1. creates the `~/GPTK` folder;
2. copies itself to `~/GPTK/MacGaming.sh` (executable, quarantine flag removed);
3. adds the `macgaming` shortcut to `~/.zshrc`.

The file in `~/Downloads` can be deleted afterwards. From then on:

```bash
macgaming          # opens the menu (in a new Terminal window)
macgaming 4        # runs a menu option directly
~/GPTK/MacGaming.sh
```

For a fresh install, use **option 1 (Full install)**.

---

## Menu

```
  1) Full install
  2) Install/update apps (Steam, CrossOver, NotProton)
  3) Download/install/switch GPTK build (4.0b3, 3.0, 2.1 or local DMG)
  4) Apply GPTK to NotProton (Steam games)
  5) Apply GPTK to game prefixes
  6) Apply GPTK to CrossOver.app
  7) Apply to everything (4 + 5 + 6)
  8) Check versions
  9) Restore backup
 10) Uninstall everything
  0) Exit
```

| Option | What it does |
|---|---|
| **1** | Prerequisites → apps → GPTK build → applies to everything |
| **2** | `brew install/upgrade --cask` for `steam`, `crossover` and `notprotonnot/notproton/notproton` |
| **3** | Choose GPTK **4.0 beta 3**, **3.0** or **2.1**: opens Apple's download in the browser (Apple ID sign-in required), waits for the DMG in `~/Downloads` and extracts it to `~/GPTK/<version>`. If the version is already installed, it just switches the `current` link. Also accepts a DMG you already have (you can drag the file into Terminal) |
| **4** | Applies to **all** NotProton `crossover-*` runners |
| **5** | Copies the DLLs into `system32` of every prefix (or of a specific APPID) |
| **6** | Finds the `apple_gptk` folder inside CrossOver.app and applies to it |
| **8** | Shows the build in use, D3DMetal versions on disk and which one the running game has loaded |
| **9** | Lists the most recent backups and restores the selected one |
| **10** | Removes apps, runners, `~/GPTK` and the shortcut — requires typing `UNINSTALL` to confirm |

### Available GPTK versions

| Version | Apple download |
|---|---|
| 4.0 beta 3 | [Evaluation_environment_for_Windows_games_4.0_beta_3.dmg](https://download.developer.apple.com/Developer_Tools/Evaluation_environment_for_Windows_games_4.0_beta_1/Evaluation_environment_for_Windows_games_4.0_beta_3.dmg) |
| 3.0 | [Evaluation_environment_for_Windows_games_3.0.dmg](https://download.developer.apple.com/Developer_Tools/Evaluation_environment_for_Windows_games_3.0/Evaluation_environment_for_Windows_games_3.0.dmg) |
| 2.1 | [Evaluation_environment_for_Windows_games_2.1.dmg](https://download.developer.apple.com/Developer_Tools/Game_Porting_Toolkit_1.1/Evaluation_environment_for_Windows_games_2.1.dmg) |

The links require signing in with an Apple ID. To add another version, add a `"<version>|<URL>"` line to the `GPTK_DOWNLOADS` array in the script.

---

## Layout

```
~/GPTK/
├── MacGaming.sh        # the script (installed automatically)
├── current -> 4.0b3    # link to the build in use
├── 4.0b3/              # one folder per version (the DMG's redist/lib)
│   ├── external/       # D3DMetal.framework, libd3dshared…
│   └── wine/           # x86_64-windows / x86_64-unix DLLs
└── backup-YYYYMMDD-HHMM/
    ├── notproton-crossover-<version>/  # original apple_gptk + target
    ├── pfx-<APPID>/                    # original DLLs + target
    └── crossover-app/
```

Switching GPTK versions = pick the build in option 3 (the `current` link then points to it) and run option 7. Previous versions remain in `~/GPTK/<version>`.

> Upgrading from an older (Portuguese) version of the script: the `~/GPTK/atual` link is automatically renamed to `~/GPTK/current`, and older backups can still be restored with option 9.

### Where the GPTK is applied

| Target | Path |
|---|---|
| Steam games (NotProton) | `~/Library/Application Support/notproton/runners/crossover-*/CrossOver/lib64/apple_gptk` |
| Game prefixes | `~/Library/Application Support/Steam/steamapps/compatdata/<APPID>/pfx/drive_c/windows/system32` |
| CrossOver.app | `apple_gptk` found inside `/Applications/CrossOver.app/Contents` |

---

## When to update

Quit Steam and any games first — the script refuses to run while they are open.

| Situation | Option |
|---|---|
| New/other GPTK version | **3**, then **7** |
| NotProton downloaded a new runner | **4** |
| New game installed | launch it once, quit, then use **5** |
| CrossOver updated | **6** |
| Apps updated | **2**, then **7** |

---

## Checking that it works

- **Metal HUD** — in the game's Steam launch options:
  ```
  MTL_HUD_ENABLED=1 %command%
  ```
  The HUD shows `Game Porting Toolkit X.X`.
- **Option 8** in the menu — versions on disk and the D3DMetal loaded by the running game.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Operation not permitted` | System Settings → Privacy & Security → **App Management** and **Full Disk Access** → allow Terminal |
| First game launch is very slow | Normal after switching GPTK: Rosetta is translating and building its cache |
| `event not found` | Don't paste the script into Terminal; run the file |
| Option 6 says there is no `apple_gptk` | That CrossOver.app version doesn't use the folder; Steam games only depend on the runner (option 4) |
| Option 3 says `redist/lib/{external,wine}` not found | That DMG has a different layout; the script lists its contents so you can check |
| Game stopped launching after applying | Option **9** to restore the backup |

---

## Uninstalling

Option **10** in the menu. Removes Steam, CrossOver, NotProton, NotProton runners, `~/GPTK` and the `macgaming` shortcut. It asks separately whether to delete app data (installed games, local saves, bottles) and whether to remove Homebrew. Rosetta 2 is kept (it is a system component).

---

## Legal notes

- This project **does not redistribute** the Game Porting Toolkit. The DMG is downloaded directly from Apple by the user, subject to Apple's license for D3DMetal.
- CrossOver is commercial software by CodeWeavers and requires a license after the trial period.
- Independent project, not affiliated with Apple, Valve, CodeWeavers or NotProton.

## Credits

- [Apple — Game Porting Toolkit](https://developer.apple.com/games/game-porting-toolkit/)
- [NotProtonNot/NotProton](https://github.com/NotProtonNot/NotProton) and [homebrew-notproton](https://github.com/NotProtonNot/homebrew-notproton)
- [CodeWeavers — CrossOver](https://www.codeweavers.com/crossover)
- [Homebrew](https://brew.sh)
