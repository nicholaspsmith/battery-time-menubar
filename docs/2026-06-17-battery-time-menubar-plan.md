# Battery Time-Remaining Menu-Bar Item Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore an estimated battery time-remaining display (bare `H:MM`) to the macOS menu bar via a small SwiftBar plugin, version-controlled in a dedicated private repo.

**Architecture:** A single shell-script SwiftBar plugin parses `pmset -g batt` and prints `H:MM` (time-to-empty while discharging, time-to-full while charging), or nothing when there is no estimate (charged / AC hold / calculating) so the item hides. The canonical script lives in a new repo at `~/Code/battery-time-menubar/` and is symlinked into `~/.config/SwiftBar/` so the live menu-bar item is the version-controlled file.

**Tech Stack:** Bash, `pmset`, SwiftBar, git, GitHub (`gh`).

## Global Constraints

- Menu-bar output is the bare `H:MM` only — no glyphs, no percentage, no dropdown.
- Show nothing (empty stdout) whenever macOS reports no time estimate.
- Plugin filename must be `battery-time.30s.sh` (the `.30s.` sets SwiftBar's 30s refresh).
- The live plugin in `~/.config/SwiftBar/` is a symlink to the repo copy; only plugin files may live in that folder.
- Repo: `~/Code/battery-time-menubar`, private GitHub remote, single atomic initial commit, pushed.
- Commit messages end with: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`

---

### Task 1: Plugin script + fixture tests (TDD)

**Files:**
- Create: `~/Code/battery-time-menubar/battery-time.30s.sh`
- Test: `~/Code/battery-time-menubar/test/test_battery_time.sh`

**Interfaces:**
- Produces: an executable script that reads `pmset -g batt` (or `$PMSET_FIXTURE` if set) and prints `H:MM` or nothing.
- The `PMSET_FIXTURE` env var override is the seam that makes the script testable without real battery state.

- [ ] **Step 1: Write the failing test**

Create `test/test_battery_time.sh`:

```bash
#!/usr/bin/env bash
# Fixture-based tests for battery-time.30s.sh
set -u

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/battery-time.30s.sh"
fail=0

check() {
  local name="$1" fixture="$2" expected="$3" got
  got="$(PMSET_FIXTURE="$fixture" "$SCRIPT")"
  if [ "$got" = "$expected" ]; then
    printf 'ok   - %s\n' "$name"
  else
    printf 'FAIL - %s: expected [%s] got [%s]\n' "$name" "$expected" "$got"
    fail=1
  fi
}

DISCHARGING="Now drawing from 'Battery Power'
 -InternalBattery-0 (id=50921571)	22%; discharging; 1:52 remaining present: true"
CHARGING="Now drawing from 'AC Power'
 -InternalBattery-0 (id=50921571)	80%; charging; 1:20 remaining present: true"
NOEST="Now drawing from 'Battery Power'
 -InternalBattery-0 (id=50921571)	50%; discharging; (no estimate) present: true"
CHARGED="Now drawing from 'AC Power'
 -InternalBattery-0 (id=50921571)	100%; charged; 0:00 remaining present: true"
ACHOLD="Now drawing from 'AC Power'
 -InternalBattery-0 (id=50921571)	80%; AC attached; not charging present: true"

check "discharging shows time-to-empty" "$DISCHARGING" "1:52"
check "charging shows time-to-full"     "$CHARGING"    "1:20"
check "no estimate prints nothing"      "$NOEST"       ""
check "charged prints nothing"          "$CHARGED"     ""
check "ac hold prints nothing"          "$ACHOLD"      ""

exit $fail
```

- [ ] **Step 2: Run test to verify it fails**

```bash
chmod +x ~/Code/battery-time-menubar/test/test_battery_time.sh
~/Code/battery-time-menubar/test/test_battery_time.sh
```
Expected: FAIL — the script does not exist yet (non-zero exit, errors about missing `battery-time.30s.sh`).

- [ ] **Step 3: Write minimal implementation**

Create `battery-time.30s.sh`:

```bash
#!/usr/bin/env bash
# battery-time.30s.sh
# SwiftBar plugin: estimated battery time remaining as H:MM in the menu bar.
# Time-to-empty while discharging, time-to-full while charging.
# Prints nothing (item hidden) when macOS has no estimate (charged / AC hold / calculating).
#
# <bitbar.title>Battery Time Remaining</bitbar.title>
# <bitbar.version>1.0</bitbar.version>
# <bitbar.desc>Shows estimated battery time remaining (H:MM) in the menu bar.</bitbar.desc>

export PATH="/usr/bin:/bin:$PATH"

batt="${PMSET_FIXTURE:-$(pmset -g batt)}"
line="$(printf '%s\n' "$batt" | grep 'InternalBattery')"

case "$line" in
  *discharging*|*charging*)
    time="$(printf '%s\n' "$line" | grep -Eo '[0-9]{1,2}:[0-9]{2}' | head -n1)"
    [ -n "$time" ] && printf '%s\n' "$time"
    ;;
esac
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
chmod +x ~/Code/battery-time-menubar/battery-time.30s.sh
~/Code/battery-time-menubar/test/test_battery_time.sh
```
Expected: all five lines `ok   - ...`, exit 0.

- [ ] **Step 5: Sanity-check against live battery**

```bash
~/Code/battery-time-menubar/battery-time.30s.sh
```
Expected: prints current `H:MM` (matches `pmset -g batt`) if on battery/charging, or nothing if no estimate.

---

### Task 2: Install symlink, README, supporting files

**Files:**
- Create: `~/Code/battery-time-menubar/install.sh`
- Create: `~/Code/battery-time-menubar/README.md`
- Create: `~/Code/battery-time-menubar/.gitignore`
- Move: `~/.config/SwiftBar-assets/battery-time-design.md` → `~/Code/battery-time-menubar/docs/battery-time-design.md`

**Interfaces:**
- Consumes: `battery-time.30s.sh` from Task 1.
- Produces: a symlink `~/.config/SwiftBar/battery-time.30s.sh` → repo script, making the plugin live.

- [ ] **Step 1: Create `install.sh`**

```bash
#!/usr/bin/env bash
# Symlink the plugin into the SwiftBar plugin folder.
set -euo pipefail
PLUGIN_DIR="${SWIFTBAR_PLUGIN_DIR:-$HOME/.config/SwiftBar}"
SRC="$(cd "$(dirname "$0")" && pwd)/battery-time.30s.sh"
mkdir -p "$PLUGIN_DIR"
ln -sf "$SRC" "$PLUGIN_DIR/battery-time.30s.sh"
echo "Linked $SRC -> $PLUGIN_DIR/battery-time.30s.sh"
echo "Reload SwiftBar to pick it up immediately (or wait for its refresh)."
```

- [ ] **Step 2: Create `.gitignore`**

```gitignore
.DS_Store
```

- [ ] **Step 3: Create `README.md`**

```markdown
# battery-time-menubar

A tiny [SwiftBar](https://github.com/swiftbar/SwiftBar) plugin that restores the
estimated battery **time remaining** (`H:MM`) to the macOS menu bar — Apple
removed the always-visible estimate in Sierra (2016).

- Discharging → time to empty (e.g. `1:52`)
- Charging → time to full (e.g. `1:20`)
- Charged / on-AC hold / still calculating → nothing (the item hides)

Bare `H:MM` only — no glyphs, no percentage, no dropdown.

## Requirements

- macOS with a battery (laptop)
- [SwiftBar](https://github.com/swiftbar/SwiftBar) (`brew install swiftbar`)

## Install

```sh
./install.sh
```

This symlinks `battery-time.30s.sh` into `~/.config/SwiftBar/` (override with
`SWIFTBAR_PLUGIN_DIR`). Reload SwiftBar, then ⌘-drag the item to sit beside the
battery icon.

## Test

```sh
./test/test_battery_time.sh
```

Fixture-driven: feeds captured `pmset -g batt` outputs via `PMSET_FIXTURE` and
checks the printed line.

## Uninstall

```sh
rm ~/.config/SwiftBar/battery-time.30s.sh
```
```

- [ ] **Step 4: Move the design spec into the repo**

```bash
mkdir -p ~/Code/battery-time-menubar/docs
mv ~/.config/SwiftBar-assets/battery-time-design.md ~/Code/battery-time-menubar/docs/battery-time-design.md
```

- [ ] **Step 5: Run install and verify the symlink + live tests**

```bash
chmod +x ~/Code/battery-time-menubar/install.sh
~/Code/battery-time-menubar/install.sh
ls -l ~/.config/SwiftBar/battery-time.30s.sh
~/Code/battery-time-menubar/test/test_battery_time.sh
```
Expected: symlink points at the repo script; all tests `ok`.

---

### Task 3: Initialize repo, atomic commit, private remote, push

**Files:** none (git operations only).

**Interfaces:**
- Consumes: the complete working tree from Tasks 1–2.
- Produces: a private GitHub repo `battery-time-menubar` with one commit, pushed.

- [ ] **Step 1: Verify `gh` is authenticated**

```bash
gh auth status
```
Expected: logged in to github.com. If not, stop and have the user run `! gh auth login`.

- [ ] **Step 2: Initialize the repo on `main`**

```bash
git -C ~/Code/battery-time-menubar init -b main
```
Expected: empty git repo on branch `main`.

- [ ] **Step 3: Stage everything and make the single atomic commit**

```bash
git -C ~/Code/battery-time-menubar add -A
git -C ~/Code/battery-time-menubar status --short
git -C ~/Code/battery-time-menubar commit -m "$(cat <<'EOF'
feat: battery time-remaining menu-bar SwiftBar plugin

Bare H:MM estimate in the macOS menu bar via SwiftBar; hides when no
estimate. Includes fixture tests, install symlink script, README, spec.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```
Expected: one commit containing script, test, install.sh, README, .gitignore, docs/.

- [ ] **Step 4: Create the private remote and push**

```bash
gh repo create battery-time-menubar --private --source=/Users/nicholassmith/Code/battery-time-menubar --remote=origin --push
```
Expected: repo created private, `origin` set, `main` pushed.

- [ ] **Step 5: Verify remote state**

```bash
git -C ~/Code/battery-time-menubar remote -v
git -C ~/Code/battery-time-menubar log --oneline -1
gh repo view battery-time-menubar --json visibility,name -q '.name + " " + .visibility'
```
Expected: `origin` → the new repo; one commit; visibility `PRIVATE`.

---

## Self-Review

**Spec coverage:** Display behavior (discharging/charging/no-estimate), bare `H:MM`, hide-when-no-estimate, `pmset` parsing, `PMSET_FIXTURE` test seam, 30s refresh filename, symlink positioning — all mapped to Tasks 1–2. Repo/private/atomic-commit/push from the user's instruction → Task 3. No gaps.

**Placeholder scan:** No TBD/TODO; all steps carry real code and commands.

**Type consistency:** `PMSET_FIXTURE`, `battery-time.30s.sh`, and the `H:MM` regex are referenced consistently across script, tests, and install.
