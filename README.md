# RobotRunway

A native macOS menu bar app that keeps your Mac awake while AI coding assistants are working — and lets it sleep when they're done.

## The Problem

You kick off a task in Claude Code, Codex, or Gemini, walk away, and come back to find your Mac went to sleep mid-task. RobotRunway detects when AI assistants are actively working and prevents sleep until they're finished.

## Supported AI Tools

| Tool | Detection Method |
|------|-----------------|
| Claude Code (CLI) | Process name `claude` |
| Codex (CLI) | Process name `codex` |
| Gemini (CLI) | Node.js script detection |
| Claude Desktop | Electron process tree |
| Codex Desktop | Electron process tree |
| Antigravity (Gemini) | `language_server_macos_arm` process |

## How It Works

### Multi-Signal Activity Detection

RobotRunway uses three signals to reliably detect activity:

1. **CPU usage** (primary signal, weight 0.55) — Aggregate CPU of the AI process and all its children (build tools, test runners, etc.). Scored via sigmoid of z-score relative to learned idle distribution.

2. **Child process count** (weight 0.35) — When AI tools run commands, they spawn child processes. A changing process tree indicates active work.

3. **Network connections** (weight 0.10) — Any established TCP connection on port 443 indicates API communication. Low weight because HTTP/2 keeps persistent connections even when idle.

### Continuous Adaptive Learning

RobotRunway continuously learns each app's activity patterns using exponential moving averages (EMA):

- Maintains separate idle and active distributions for each signal
- Learning rate adapts with maturity: aggressive early (alpha=0.3), stable when mature (alpha=0.02)
- Per-app profiles persist across launches
- Four maturity levels: Cold Start → Learning → Developing → Mature
- Activity thresholds tighten as the profile gains confidence

### Supported Host Apps

RobotRunway monitors AI tools running inside any of these:

| App | Auto-detected |
|-----|:---:|
| Terminal.app | yes |
| iTerm2 | yes |
| Claude Desktop | yes |
| Warp | yes |
| VS Code | yes |
| Cursor | yes |
| Kitty | yes |
| Alacritty | yes |
| Hyper | yes |
| Codex Desktop | yes |
| Antigravity | yes |

On first launch, installed apps are automatically enabled. Toggle them in Settings.

## Install

### Build from source

```bash
cd RobotRunway
chmod +x build.sh
./build.sh

# Install
cp -r build/RobotRunway.app /Applications/

# Run
open /Applications/RobotRunway.app
```

### Launch at Login

System Settings → General → Login Items → add RobotRunway

## Menu Bar

The menu bar icon is a robot that animates when AI activity is detected:

- **Sleeping robot** — No activity, Mac can sleep normally
- **Animated robot** — AI is active, Mac will stay awake

The dropdown menu shows real-time details: which app the AI is running in, current CPU, active connections, profile maturity, and idle countdown progress.

## Settings

Open Settings (Cmd+,) to:

- **Enable/disable host apps** — Only monitor the apps you use
- **Reset learned profiles** — Start fresh with cautious defaults (useful if your workflow changed significantly)

The **idle threshold** (how long to stay awake after activity stops) is configurable from the menu bar: 1, 2, 3, 5, or 10 minutes. Default is 2 minutes.

## Architecture

```
main.swift                      Entry point
AppDelegate.swift               Menu bar UI, polling loop, icon animation
ActivityMonitor.swift           Multi-signal engine, continuous learning, EMA profiles
ProcessUtils.swift              Process table parsing, tree walking, AI process detection
HostApp.swift                   Host app registry, process tree matching
OnboardingWindowController.swift  First-launch app selection
SettingsWindowController.swift  Settings window UI, profile status display
SleepManager.swift              IOPMLib power assertion management
```

### State Machine

```
                         AI process found
  NO SESSION ──────────────────────────────────→ ACTIVE
  (sleep OK)                                     (stay awake)
       ↑                                              │
       │ process exits              all signals below threshold
       │                                              ↓
       │              signal resumes            IDLE COOLDOWN
       │            ┌──────────────────────── (stay awake)
       │            │                               │
       │            │                     threshold exceeded
       │            │                               ↓
       └────────────┴─────────────────────────── IDLE
                                                 (sleep OK)
```

## Technical Notes

- **No dock icon** — Runs as a menu bar agent (`LSUIElement = true`)
- **No special permissions** — Uses `ps` and `lsof` for process info, IOPMLib for sleep control
- **Polls every 0.5 seconds** — `ps` for process table, `lsof` for network connections
- **Process tree walking** — Traces from AI process up through the tree to identify the host app
- **Requires macOS 13+** (Ventura)

## Troubleshooting

**"No AI coding session found" but an AI tool is running:**
- Make sure the host app is enabled in Settings
- Check that the AI CLI process is running (e.g., `ps aux | grep claude`)

**Mac still sleeps during active work:**
- Reset learned profiles in Settings — the profile may have learned incorrect patterns
- Try increasing the idle threshold to 5 or 10 minutes

**Verify power assertions from Terminal:**
```bash
pmset -g assertions | grep RobotRunway
```
