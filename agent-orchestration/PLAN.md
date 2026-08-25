# Agent Orchestration Plan

> The setup: AeroSpace workspaces 1–0 that **auto-open on every login**.
> - **WS1** = Arc browser
> - **WS2** = one plain, fresh local shell (you drive it; launch claude here as Director when you want)
> - **WS3** = 4 separate Ghostty windows, each attached to a fleet slot on the **mac mini** (persistent tmux sessions `a1`–`a4`, `claude` booted by `start.sh`)
>
> **Now (2026-08-24): the MAC MINI is the brain.** Conductors are persistent tmux
> sessions `a1`–`a4` ON THE MINI; the MacBook (and later the PC) is a thin viewer
> — WS3 windows and `prefix+1-0` (§11) both just ssh-attach. Close the laptop,
> the fleet keeps running. (The old "PC/WSL as source of truth" idea is dead —
> the PC is NOT the brain, the mini is.)

Status: **BUILT & VALIDATED on the Mac** — syntax, local tmux, `claude`, the Ghostty
`-e` launch, and the AeroSpace config all checked. Not yet *run* (one command, below).

## ▶ Turn it on / stop / revert

Built + wired:
- `scripts/start.sh` (ensures slot sessions `a1`–`a4` on the MINI, each running claude),
  `scripts/attach.sh` (attach this terminal to slot N on the mini; wraps
  `~/.config/tmux/mini-attach.sh`), `scripts/layout.sh` (the launcher) — all executable.
- `~/.config/aerospace/aerospace.toml` — workspaces 1–0 bound (`cmd-1`…`cmd-9`, `cmd-0`
  + `cmd-shift-N` to move), Arc routed to WS1, and `after-startup-command` runs
  `layout.sh` on login. Original saved at `aerospace.toml.bak-pre-agents`.

**Launch it now** (opens 7 windows; also runs on every login afterwards):
```
~/.config/agent-orchestration/scripts/layout.sh
```
Expect Arc on WS1, a plain shell on WS2, 4 windows tiled on WS3 each attached to
mini slots `a1`–`a4` with `claude` running (or sitting at a retry prompt if the
mini is down — press `r` there once it's awake).

**Stop the fleet:** `ssh mac-mini tmux kill-session -t =a1` (per slot), or
`ssh mac-mini tmux kill-server` to flatten every session on the mini.
**Pause autostart:** comment out the `after-startup-command` line + `aerospace reload-config`.
**Revert WM changes:** `cp ~/.config/aerospace/aerospace.toml.bak-pre-agents
~/.config/aerospace/aerospace.toml && aerospace reload-config`.

---

## 1. The workspace layout (the centerpiece)

```
 WS1: ARC                WS2: PLAIN SHELL (you drive)   WS3: THE FLEET (4 windows)
 ┌────────────────┐      ┌──────────────────────────┐   ┌───────────┬───────────┐
 │  Arc           │      │  Ghostty                 │   │  web      │  mobile   │
 │  localhost     │      │   plain local shell      │   │  claude   │  claude   │
 │  Vercel        │      │   (fresh, 1 tab)         │   ├───────────┼───────────┤
 │  Supabase      │      │                          │   │  learn    │  ops      │
 │  docs          │      │  launch claude here when │   │  claude   │  claude   │
 │                │      │  you want a Director     │   │           │           │
 └────────────────┘      └──────────────────────────┘   └───────────┴───────────┘
```

The tree, made concrete:

| Tier | Lives in | What it is |
|------|----------|------------|
| **You** | WS2 plain shell | launch `claude` here to act as Director when you want to dispatch |
| **Fleet** (4 conductors) | WS3, 4 Ghostty windows → local tmux sessions `web`/`mobile`/`learn`/`ops` (later: WSL) | each owns a domain, claims tasks, runs loops; `claude` already running |
| **Looping sub-agents** | inside each conductor | Workflow / /loop / ralph-loop workers |

---

## 2. Source of truth = the PC (recommended)

Everything runs in **persistent tmux inside WSL on the PC**; the Mac's Ghostty
windows just `ssh wsl` into WSL and `tmux attach`. Why:
- One filesystem = one real source of truth (no rsync split-brain for task state).
- **Loops survive** Mac sleep / disconnect / closing the lid — they keep running
  on the PC. This is the whole point of a fleet; laptop-local loops die on sleep.
- Reattach from anywhere and the fleet is exactly where you left it.

Alternative (run locally + rsync the board) is possible but races on the shared
files and dies on sleep — not recommended.

---

## 3. The four fleet conductors (WS3 panes)

| Pane | Conductor | Owns |
|------|-----------|------|
| top-left | **web** | startup-dashboard, trutide-web, net-worth-tracker, omnipost, kakitori-web, kakitori-education (Next 16 / Supabase / Vercel) |
| top-right | **mobile** | kakitori-app, modern-blue-insights/mobile (Expo 56, EAS) |
| bottom-left | **learn** | learn-rust, learn-c, ml-fundamentals, algorithm_practice, neural-net-playground — runs with the **learning** output style |
| bottom-right | **ops** | cross-repo sweeps, deploys, dependency updates, scheduled routines |

The **Director (WS2)** is the only one you talk to day-to-day. It decomposes work
into task files and drops them on the board; the fleet picks them up.

---

## 4. Coordination — the shared task board

Cross-pane coordination isn't native; the mechanism is a shared directory on the
PC (one filesystem, so claims are atomic):

```
~/.config/agent-orchestration/
  PLAN.md
  charters/   dev.md web.md mobile.md learn.md ops.md   <- standing brief per agent
  board/
    inbox/        <- Director drops task-XXX.md (status: open, domain: web|mobile|…|any)
    claimed/      <- a conductor MOVES the file here to claim it (atomic lock)
    done/         <- moved here on completion, with result appended
  logs/           <- per-conductor append-only run notes
  scripts/        <- start.sh (PC) + layout.sh (Mac)  ← autostart, section 7
```

**Claim = move the file.** A move is atomic on one filesystem, so two conductors
can't grab the same task. Task file:
```markdown
---
id: task-007
domain: web        # web|mobile|learn|ops|any
status: open       # open -> claimed -> done
priority: 2
---
Migrate net-worth-tracker to React 19, run tests, deploy a preview, report URL.
```

---

## 5. Looping primitives — when to use which

| Primitive | Use for | Runs where | Survives disconnect? |
|-----------|---------|------------|----------------------|
| **Workflow** | structured fan-out + loop-until-done over a worklist | conductor (PC) | yes |
| **/loop** | re-run on an interval / self-paced (babysit deploy, poll build) | conductor (PC) | yes |
| **ralph-loop** plugin | "grind on THIS until the goal is met" (Stop-hook re-invoke) | conductor (PC) | yes |
| **/schedule** | recurring cron ("Mon 8am brief") | **cloud** | yes (even if PC off) |

Loops need a self-checkable stop condition → **tests**. Only 2 of your 11 repos
have them; add a thin Vitest setup to the Next apps before expecting autonomous
loops there. Loop workers must run with `--dangerously-skip-permissions` (your
alias already does) or they hang on prompts.

---

## 6. Cost & effort tiering

4 fleet panes + Director, all on `opus[1m]`/`xhigh`, is a heavy concurrent rate.
- Director: `high`/`xhigh` (you steer, quality matters).
- Fleet loop workers: `medium`, or `low` for mechanical edits (Workflow `agent()`
  takes a per-agent `effort` override).
- Keep most panes idle; run 1–2 hot at a time. Cap big fan-outs with budget
  directives. Expect rate-limit pressure if all 5 fan out at once.

---

## 7. Autostart — "open like this every time"

> ⚠️ SUPERSEDED BY THE ACTUAL SCRIPTS. The canonical implementation is now in
> `scripts/start.sh` (WSL), `scripts/attach.sh` + `scripts/layout.sh` (Mac), and
> the wired `aerospace.toml`. It uses **4 separate Ghostty windows** (your choice),
> not the 2×2 tmux panes sketched below, and WSL paths are under `~/` (not
> `~/Documents`). The notes below are kept for design context only.

Two pieces: **(a)** a script on the PC that builds the tmux sessions, **(b)**
AeroSpace on the Mac launches the windows into the right workspaces at login.

### (a) PC: `~/agent-hq/start.sh` — build the sessions (idempotent)
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$HOME/Documents"

# Director: single window
tmux has-session -t dev 2>/dev/null || tmux new-session -d -s dev -c "$HOME/Documents"

# Fleet: one session, 4 panes in a 2x2 tiled grid
if ! tmux has-session -t fleet 2>/dev/null; then
  tmux new-session -d -s fleet -c "$HOME/Documents"          # pane 0
  tmux split-window -t fleet -c "$HOME/Documents"            # pane 1
  tmux split-window -t fleet -c "$HOME/Documents"            # pane 2
  tmux split-window -t fleet -c "$HOME/Documents"            # pane 3
  tmux select-layout -t fleet tiled                          # -> clean 2x2
  # optional: auto-launch a conductor in each pane
  # tmux send-keys -t fleet.0 'claude  # web'    C-m
  # tmux send-keys -t fleet.1 'claude  # mobile' C-m
  # tmux send-keys -t fleet.2 'claude  # learn'  C-m
  # tmux send-keys -t fleet.3 'claude  # ops'    C-m
fi
tmux ls
```
This script lives & runs **inside WSL** on the PC. Trigger it from the Mac with
`ssh wsl 'bash -lc ~/agent-hq/start.sh'`, or have WSL run it on boot (systemd
user service / `~/.profile` guard / cron `@reboot`) so the sessions always wait.

### (b) Mac: `scripts/layout.sh` — open windows into workspaces
```bash
#!/usr/bin/env bash
BROWSER_APP="Arc"   # <-- set to your browser (Arc / Google Chrome / Safari)

# WS1: browser
aerospace workspace 1
open -a "$BROWSER_APP"

# Use the 'wsl' ssh host: it connects straight into WSL on the PC and (per your
# ~/.ssh/config) multiplexes via ControlMaster, so both windows share ONE
# connection. Do NOT use 'desktop' here — it force-runs `wsl --cd ~` and ignores
# the tmux command.

# WS2: Director
aerospace workspace 2
open -na Ghostty --args --title=dev   -e ssh wsl -t "tmux attach -t dev"

# WS3: Fleet (the 2x2 lives inside tmux, so one Ghostty window is enough)
aerospace workspace 3
open -na Ghostty --args --title=fleet -e ssh wsl -t "tmux attach -t fleet"

sleep 1
aerospace workspace 2   # land you on the Director
```

### (c) Mac: wire it into AeroSpace login (`~/.config/aerospace/aerospace.toml`)
```toml
start-at-login = true
after-startup-command = [
  'exec-and-forget ~/.config/agent-orchestration/scripts/layout.sh'
]

# Route by window title so the two Ghostty windows land correctly
[[on-window-detected]]
if.window-title-regex-substring = 'dev'
run = ['move-node-to-workspace 2']

[[on-window-detected]]
if.window-title-regex-substring = 'fleet'
run = ['move-node-to-workspace 3', 'layout tiles']

[[on-window-detected]]
if.app-id = '<BROWSER_BUNDLE_ID>'   # e.g. com.google.Chrome
run = ['move-node-to-workspace 1']
```

> Design choice baked in: **WS3 is ONE Ghostty window split 2×2 by tmux**, not 4
> separate windows. It's far more reliable to reproduce on every boot and the
> grid is exact. (Alternative — 4 real windows tiled by AeroSpace — is noted in
> §10 if you'd rather have OS-level windows.)

---

## 8. Setup checklist (phased)

**Phase 0 — prereqs:** `claude` installed & authed **inside WSL** on the PC ·
`ssh wsl` reaches WSL directly · tmux installed in WSL · browser chosen.
**Phase 1 — PC sessions:** create `start.sh`, run it, confirm `dev` + `fleet` (2×2) exist.
**Phase 2 — Mac autostart:** add `layout.sh`, wire `aerospace.toml` (§7c), test by
running `layout.sh` manually, then by logout/login.
**Phase 3 — charters:** write `charters/{dev,web,mobile,learn,ops}.md`; Director reads
`dev.md`, each fleet pane reads its own + global `~/.claude/CLAUDE.md`.
**Phase 4 — board:** `mkdir -p board/{inbox,claimed,done}`; run one end-to-end test task.
**Phase 5 — loops on:** enable `learning-output-style` + `ralph-loop`; first Workflow loop.
**Phase 6 — schedules:** `/schedule` a Monday data brief + a weekly cross-repo sweep.

---

## 9. Honest caveats

1. **~2 effective tiers of agents**, not infinite nesting: Director → Workflow → workers.
2. **Coordination is a convention** (move-to-claim), reliable only on one filesystem (PC).
3. **`/schedule` runs in the cloud** — commit/push anything it needs; it can't see local-only state.
4. **Cost** scales with hot panes — tier effort, keep panes idle by default.
5. **Loops need tests** to self-terminate — add minimal Vitest to the Next repos.
6. **Autostart timing**: `open` + `aerospace workspace` can race; the title-based
   `on-window-detected` rules (§7c) are the robust fallback if the script ordering drifts.

---

## 10. Open decisions for you
- [ ] **WS3 = one Ghostty + tmux 2×2 (recommended)** vs **4 separate Ghostty windows** tiled by AeroSpace.
- [ ] **Browser** for WS1 (Chrome / Arc / Safari / …).
- [ ] **Domain split** web/mobile/learn/ops — good, or a different 4-way cut?
- [ ] **Build the autostart now**, or keep plan-only a bit longer?

---

## 11. Mini as the brain (2026-08-24)

Decision update: the **source-of-truth machine is the mac mini**, not PC/WSL
(mini is always-on-capable, macOS, already the ssh target for renders/agents).

**Built:**
- **prefix+1-0 slot windows** (MacBook `~/.config/tmux/tmux.conf`): `C-b 1`…`C-b 0`
  jumps to (or opens) window `m1`…`m10` in the current session, each ssh-attached
  to persistent tmux session `a1`…`a10` on the mini — created on demand, survive
  disconnects/laptop lid. Root-level `C-digit`/`M-digit` bindings untouched.
  Window command: `~/.config/tmux/mini-attach.sh <slot>` (retry prompt if mini down).
  Detach a slot: `C-b C-b d` (double prefix reaches the inner tmux); the window closes.
- **`mini/tmux.conf`** — the mini-side server conf (mouse scrollback, green status
  bar = "you're on the mini", `window-size latest` so multiple viewers don't
  shrink each other). Push with **`scripts/push-mini-conf.sh`** when the mini is awake.

**Same bindings from the PC:** paste the `prefix+1-0` block + `mini-attach.sh`
into the WSL tmux setup and add the `mac-mini` Host entry to the PC's ssh config.

**Fleet migration — DONE (same day):** slots `a1`–`a4` ARE the fleet now. The
old one-session/2×2-panes `fleet` design is gone (it also had every WS3 window
mirroring the same grid). `start.sh` ensures `a1`–`a4` exist on the mini with
`claude` running (idempotent; leaves existing slots alone), `attach.sh N` =
viewer for slot N, and `layout.sh` runs `start.sh` then opens the four WS3
windows on `mini-attach.sh 1`–`4`. Nothing fleet-shaped runs on the MacBook.
**Still to move: PocketFleet's bridge** (`~/Documents/PocketFleet`) — it reads
the MacBook's tmux server; repoint it at the mini (run the bridge there).

**Prereq on the mini (once, while physically there or via Screen Sharing):**
`sudo pmset -a sleep 0 displaysleep 10` — it's a server now; asleep-mini is the
only failure mode of the whole scheme (Tailscale showed it offline 1d as of this note).
