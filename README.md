# ClaudeAwake ☕

A native macOS menu bar app that keeps your Mac awake while Claude Code is working — and lets it sleep when Claude is done.

## The Problem

You kick off a Claude Code task, walk away, and come back to find your Mac went to sleep mid-task. ClaudeAwake solves this by intelligently detecting when Claude Code is actively working and preventing sleep until it's finished.

## How It Works

### Multi-Signal Activity Detection

Unlike simple CPU-threshold approaches, ClaudeAwake uses three signals to reliably detect activity:

1. **Network connections to Anthropic's API** (strongest signal) — When Claude Code is thinking or generating, it maintains a streaming connection to `api.anthropic.com`. When idle at the prompt, there are no connections. Detected via `lsof`.

2. **CPU usage** (corroborating signal) — Aggregate CPU of the `claude` process and all its children (build tools, test runners, etc.). Compared against a learned baseline rather than a fixed threshold.

3. **Child process count** (supporting signal) — When Claude Code runs commands, it spawns child processes. A changing process tree indicates active work.

If **any** signal is above baseline → Mac stays awake.
If **all** signals are at baseline for the full idle threshold → Mac can sleep.

### Adaptive Baseline Calibration

Every terminal app has different baseline resource usage. ClaudeAwake automatically calibrates when it first detects Claude Code running in each app:

- Samples activity for ~30 seconds
- Records median CPU, network connections, and child process count
- Calculates a safe margin above baseline
- Stores per-app, persists across launches
- Can be reset anytime from Settings

### Supported Host Apps

ClaudeAwake monitors Claude Code running inside any of these:

| App | Auto-detected |
|-----|:---:|
| Terminal.app | ✓ |
| iTerm2 | ✓ |
| Claude Desktop | ✓ |
| Warp | ✓ |
| VS Code | ✓ |
| Cursor | ✓ |
| Kitty | ✓ |
| Alacritty | ✓ |
| Hyper | ✓ |

On first launch, installed apps are automatically enabled. You can toggle them in Settings.

## Install

### Build from source

```bash
cd ClaudeAwake
chmod +x build.sh
./build.sh

# Install
cp -r build/ClaudeAwake.app /Applications/

# Run
open /Applications/ClaudeAwake.app
```

### Launch at Login

System Settings → General → Login Items → add ClaudeAwake

## Menu Bar

Click the icon to see:

| Icon | Meaning |
|------|---------|
| ☕ `cup.and.saucer.fill` | Claude Code is active — Mac will stay awake |
| 😴 `moon.zzz` | No activity — Mac can sleep normally |
| ⏸ `pause.circle` | Monitoring paused by user |

The menu shows real-time details: which app Claude is running in, current CPU, active network connections, and idle countdown progress.

## Settings

Open Settings (⌘,) to:

- **Enable/disable host apps** — Only monitor the terminals you use
- **Reset calibrations** — Force re-learning of baselines (useful if your workflow changed)

The **idle threshold** (how long to wait after activity stops before allowing sleep) is configurable from the menu bar: 1, 2, 3, 5, or 10 minutes. Default is 2 minutes.

## Architecture

```
main.swift                    Entry point
AppDelegate.swift             Menu bar UI, polling loop, sleep control
ActivityMonitor.swift         Multi-signal engine, state machine, calibration
ProcessUtils.swift            Process table parsing, tree walking, shell commands
HostApp.swift                 Host app registry, detection, preferences
SettingsWindowController.swift  Settings window UI
SleepManager.swift            IOPMLib power assertion management
```

### State Machine

```
┌─────────────┐   claude process found   ┌─────────────────────┐
│  NO SESSION  │ ──────────────────────→  │  CALIBRATING (30s)  │
│  sleep OK    │                          │  stay awake          │
└─────────────┘                           └──────────┬──────────┘
       ↑                                              │
       │ process exits                    calibration complete
       │                                              ↓
       │                                  ┌─────────────────────┐
       │          any signal active       │      ACTIVE          │
       │        ┌─────────────────────── │  stay awake          │
       │        │                         └──────────┬──────────┘
       │        │                                     │
       │        │                        all signals at baseline
       │        │                                     ↓
       │        │                         ┌─────────────────────┐
       │        └──────────────────────── │  IDLE COOLDOWN       │
       │                                  │  stay awake          │
       │                                  └──────────┬──────────┘
       │                                              │
       │                                   threshold exceeded
       │                                              ↓
       │                                  ┌─────────────────────┐
       └────────────────────────────────  │      IDLE            │
                                          │  sleep OK            │
                                          └─────────────────────┘
```

## Technical Notes

- **No dock icon** — Runs as a menu bar agent (`LSUIElement = true`)
- **No special permissions** — Uses `ps` and `lsof` for process info, IOPMLib for sleep control
- **Low overhead** — Polls every 5 seconds; `ps` + `lsof` are lightweight
- **Process tree walking** — Traces from `claude` process up through the tree to identify the host app
- **Requires macOS 13+** (Ventura) for SF Symbols in the menu bar

## Troubleshooting

**"No Claude Code session found" but Claude Code is running:**
- Make sure the host app is enabled in Settings
- Check that the `claude` CLI is the process name (not a wrapper script with a different name)

**Mac still sleeps during active work:**
- Reset calibrations in Settings — the baseline may be stale
- Try increasing the idle threshold to 5 or 10 minutes
- Check Activity Monitor to verify ClaudeAwake's power assertion is active (search for "ClaudeAwake" in assertions)

**Verify power assertions from Terminal:**
```bash
pmset -g assertions | grep ClaudeAwake
```
