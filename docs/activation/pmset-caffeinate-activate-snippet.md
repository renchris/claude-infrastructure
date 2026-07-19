# pmset + caffeinate — activation snippet (T-P16-3 / T-P16-4)

**C10 ceiling:** the agent BUILDS + RED-proves `scripts/power-policy-verify.sh` (T-P16-3, AC-policy
drift → page) and `scripts/caffeinate-floor.sh` (T-P16-4, the persistent idle-sleep floor) and
authors the two plists. The **operator** performs the one-time `sudo pmset` apply and loads the two
LaunchAgents. Nothing here edits `settings.json`, a live hook, or a loaded plist **in place** — this
file (and `pending-activation/05-pmset-caffeinate-activate.sh`) is the hand-off. A user LaunchAgent
has no root, so the verifier can only VERIFY + PAGE; the `sudo pmset -c …` re-assert is always the
operator's action.

## What was built (repo files, on `feat/desk-pmset-caffeinate`)

| Artifact | Kind | Needs operator action? |
|---|---|---|
| `scripts/caffeinate-floor.sh` | floor runner: `--run` exec's `caffeinate -i -s`; `--verify`; `--selftest` | load the plist below |
| `scripts/power-policy-verify.sh` | AC-policy verifier: `--verify` (drift → page); `--selftest` | one-time `sudo pmset` + load the plist below |
| `launchd/com.claude.caffeinate-floor.plist` | RunAtLoad + KeepAlive → holds the idle-sleep assertion forever | `cp` + `launchctl bootstrap` |
| `launchd/com.claude.power-policy-verify.plist` | RunAtLoad + hourly → verifies AC policy, pages on drift | `cp` + `launchctl bootstrap` |
| `tests/power-policy.bats` (+ both `--selftest`s) | RED-proofs of the exit contracts + page shape | none (CI / nightly-regression) |

## The intended AC (charger) power policy — the load-bearing 24/7 keys

```
sleep=0   displaysleep=0   disablesleep=0        (a key absent from `pmset -g custom`'s AC block ⇒ 0)
```

`sleep=0` (system never idle-sleeps on AC) is the load-bearing key — the reason a 6-day uptime holds
even when every session idles. It is otherwise a **manual, out-of-band** setting (p16 G-P16-3): an OS
update / SMC-NVRAM reset / a new machine silently reverts it to the default idle-sleep profile, at
which point the desk starts sleeping. `power-policy-verify` re-reads it at every login (RunAtLoad) and
hourly, and PAGES (autonomy/pages/ → desk-role consumer + an osascript notification) naming the exact
`sudo pmset -c …` remediation.

## Battery-policy note (loading the floor plist RATIFIES this — operator decision G-P16-2)

The floor runs `caffeinate -i -s` by default:
- `-i` prevents **idle system sleep on AC *and* battery** — this is what covers the hostile battery
  `sleep 1` profile so the machine stays awake while docked & away on battery.
- `-s` prevents system sleep on AC only (harmless on battery).

Tradeoff to weigh before loading: on a **sustained power outage** the machine runs on its internal
battery (a healthy built-in UPS — p16 §6). With `-i` the machine stays fully awake and burns that
battery faster, so a long outage reaches a hard shutdown (→ FileVault lock) sooner than if it had been
allowed to sleep. If you prefer "preserve UPS runtime through an outage, accept that sessions freeze on
battery," downgrade the floor to AC-only by setting `CC_CAFFEINATE_FLAGS=-s` in the plist's
`EnvironmentVariables` (or `~/.zshenv`) before loading. The default (`-i -s`) is the "stay awake for
24/7 even on battery while docked" posture that T-P16-4 specifies.

## Step 1 — land `feat/desk-pmset-caffeinate` via the project-local `/ship`

The plists reference `$HOME/Development/claude-infrastructure/scripts/…` (the landed main-checkout
path), so land first.

## Step 2 — one-time `sudo pmset` AC apply (operator, interactive root)

```sh
sudo pmset -c sleep 0 displaysleep 0 disablesleep 0
pmset -g custom | sed -n '/AC Power:/,$p'      # confirm sleep 0 / displaysleep 0
```

If your macOS build rejects the `disablesleep` token, drop it — `sleep 0 displaysleep 0` are the
always-valid, load-bearing pair (and edit `CC_PMSET_INTENDED_AC` / `CC_PMSET_REMEDIATE` in the plist
env to match so the verifier does not page for a key you deliberately omit).

## Step 3 — load the two LaunchAgents (floor FIRST, then the verifier)

Loading the floor before the verifier means the verifier's RunAtLoad pass sees the floor already
asserting (no spurious "floor absent" note on the first run).

```sh
for L in com.claude.caffeinate-floor com.claude.power-policy-verify; do
  cp "$HOME/Development/claude-infrastructure/launchd/$L.plist" "$HOME/Library/LaunchAgents/$L.plist"
  plutil -lint "$HOME/Library/LaunchAgents/$L.plist"
  launchctl bootout  "gui/$(id -u)/$L" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/$L.plist"
done
```

(Or run `pending-activation/05-pmset-caffeinate-activate.sh` with `CONFIRM=1`, which does steps 2–3.)

## Verify (the two acceptance criteria)

```sh
# T-P16-4: a caffeinate assertion is present with ZERO active CC turns (the floor, no -t timeout):
pmset -g assertions | grep -E 'caffeinate' | grep -v -- '-t'
~/Development/claude-infrastructure/scripts/caffeinate-floor.sh --verify      # → PRESENT, exit 0

# T-P16-3: the AC policy matches intent after a login/reboot, and drift pages:
~/Development/claude-infrastructure/scripts/power-policy-verify.sh --verify   # → GREEN, exit 0
launchctl print "gui/$(id -u)/com.claude.power-policy-verify" | grep -E 'state|program|runatload'
```

## Rollback

```sh
for L in com.claude.caffeinate-floor com.claude.power-policy-verify; do
  launchctl bootout "gui/$(id -u)/$L" 2>/dev/null || true
  rm -f "$HOME/Library/LaunchAgents/$L.plist"
done
# The pmset AC policy is durable (survives the bootout). To revert it too (rarely wanted):
sudo pmset -c sleep 1        # restore a 1-min idle sleep on AC (the macOS-ish default)
```
