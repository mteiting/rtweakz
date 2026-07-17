# RTweakz

A lightweight World of Warcraft addon that automatically adjusts your FPS cap based on what you're doing. Save power and keep your machine cool in the open world — get full frames where it counts.

## How it works

RTweakz sets the `maxFPS` cvar based on your current context, checked in this priority order:

| Context | Default cap |
|---|---|
| AFK | 30 FPS |
| Instance (dungeon, raid, arena, battleground, scenario) | 144 FPS |
| Rested area (inn, city) | 45 FPS |
| Open world | 60 FPS |

All values are configurable. A value of `0` means uncapped.

## PI request alert

Optionally, RTweakz can alert you when someone asks for Power Infusion. When enabled, a whisper or party chat message containing one of the configured keywords (default: `pi`) triggers a raid-warning banner, an alert sound, and a chat message. The sound is configurable (raid warning, ready check, alarm clock, map ping, whisper, or none) via a dropdown in the settings panel or `/rtweakz pisound <key>` — picking one plays a preview. Keywords match whole words only, so `pi` won't fire on "pizza". Battle.net whispers are covered too, and your own party chat messages are ignored.

If the requester is in your group, their Blizzard party/raid frame is also highlighted with a pulsing overlay for 5 seconds so you can find them instantly. This can be turned off with `/rtweakz pihighlight` or in the settings panel. (Battle.net whispers and custom raid frame addons are not highlighted — only the default Blizzard frames, both standard party frames and raid-style/compact frames.)

The alert is off by default — enable it with `/rtweakz pi` or the checkbox in the settings panel.

## Installation

1. Download the latest `rtweakz-<version>.zip` from the [releases page](../../releases).
2. Extract it into your AddOns folder:
   - **Windows:** `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\`
   - **macOS:** `/Applications/World of Warcraft/_retail_/Interface/AddOns/`
3. Restart the game or run `/reload`.

## Configuration

**Settings panel:** Game Menu → Options → AddOns → RTweakz, or `/rtweakz config`. Each cap has a slider (0–240) and an edit box for exact values (the edit box also accepts values above 240).

**Slash commands:**

```
/rtweakz                 show help
/rtweakz out <fps>       open world cap
/rtweakz in <fps>        instance cap
/rtweakz rested <fps>    rested area cap
/rtweakz afk <fps>       AFK cap
/rtweakz pi              toggle the PI request alert (whispers and party chat)
/rtweakz pikey <words>   set PI keywords, comma-separated (no argument: show current)
/rtweakz pihighlight     toggle unit frame highlighting on PI request
/rtweakz pisound <key>   set the alert sound (no argument: list options)
/rtweakz debug           toggle chat messages on cap changes
/rtweakz status          show current settings and active cap
/rtweakz config          open the settings panel
```

Settings are stored per account (`RTweakzDB` saved variable).

## Development

The addon consists of three files:

- `rtweakz.toc` — addon manifest
- `rtweakz.lua` — core logic: context detection, cap application, slash commands
- `rtweakz_ui.lua` — settings panel

To test local changes, symlink the repository into your AddOns folder.

**Windows** (PowerShell as administrator, or with Developer Mode enabled):

```powershell
New-Item -ItemType SymbolicLink -Path "C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\rtweakz" -Target (Get-Location)
```

**macOS / Linux:**

```sh
ln -s "$(pwd)" "/Applications/World of Warcraft/_retail_/Interface/AddOns/rtweakz"
```

## Releasing

Push a version tag to build and publish a release zip via GitHub Actions:

```sh
git tag v1.2.3
git push origin v1.2.3
```

The workflow rewrites the `## Version:` field in the `.toc` to match the tag, packages the addon as `rtweakz-1.2.3.zip`, and attaches it to a GitHub release. It can also be run manually from the Actions tab to get a dev build as a workflow artifact.
