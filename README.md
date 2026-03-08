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
| Claude Desktop | Electron main process (helpers filtered) |
| Codex Desktop | Electron main process (helpers filtered) |
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

### Quick install

```bash
curl -fsSL https://raw.githubusercontent.com/toddsherman/RobotRunway/main/install.sh | bash
```

Downloads the latest pre-built universal binary from [GitHub Releases](https://github.com/toddsherman/RobotRunway/releases). Falls back to building from source if no release is available.

### Download from Releases

Download the latest `.zip` from [GitHub Releases](https://github.com/toddsherman/RobotRunway/releases), extract it, and drag `RobotRunway.app` to `/Applications/`.

If macOS blocks the app, run:
```bash
xattr -cr /Applications/RobotRunway.app
```

### Build from source

Requires Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/toddsherman/RobotRunway.git
cd RobotRunway
make install
```

### Uninstall

```bash
make uninstall
```

### Launch at Login

System Settings → General → Login Items → add RobotRunway

## Menu Bar

The menu bar icon is a robot that animates when AI activity is detected:

- **Sleeping robot** — No activity, Mac can sleep normally
- **Animated robot** — AI is active, Mac will stay awake

The dropdown menu shows real-time status:

- **AI activity detected** — At least one AI tool is actively working
- **Forcing awake for X** — Activity stopped, staying awake during cooldown
- **AI apps idle for X** — All AI tools idle, Mac can sleep normally

## Settings

Open Settings (Cmd+,) to:

- **Enable/disable host apps** — Only monitor the apps you use
- **Reset learned profiles** — Start fresh with cautious defaults (useful if your workflow changed significantly)

The **idle threshold** (how long to stay awake after activity stops) is configurable from the menu bar: 1, 2, 3, 5, or 10 minutes. Default is 2 minutes.

## Activity Log

Open the Activity Log (Cmd+L or from the menu bar) to see a real-time chart of all polling data from the last 10 minutes.

The chart plots five signals on a 0.0–1.0 scale:

- **Score** (blue, thick) — Weighted composite activity score
- **CPU** (orange) — Aggregate CPU usage, normalized per-app
- **Network** (green) — Established TCP connections on port 443
- **Children** (purple) — Child process count
- **Threshold** (red) — Current activity threshold, plotted over time as it adapts with profile maturity

Active regions are highlighted with a light green background. The chart shows roughly one minute of data in the visible window, with the remaining nine minutes accessible via horizontal scrolling. The y-axis and legend remain fixed while scrolling.

Tabs along the top let you filter by individual app or view all apps combined.

## Architecture

```
main.swift                       Entry point
AppDelegate.swift                Menu bar UI, polling loop, icon animation
ActivityMonitor.swift            Multi-signal engine, continuous learning, EMA profiles
ProcessUtils.swift               Process table parsing, tree walking, AI process detection
HostApp.swift                    Host app registry, process tree matching
ActivityChartView.swift          Real-time multi-signal chart (Core Graphics)
LogWindowController.swift        Activity Log window, tabs, legend, scroll view
OnboardingWindowController.swift First-launch app selection
SettingsWindowController.swift   Settings window UI, profile status display
SleepManager.swift               IOPMLib power assertion management
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
- **Electron helper filtering** — Skips GPU, renderer, and utility helper processes to avoid false positives from Electron-based apps
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
