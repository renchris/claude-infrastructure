#!/usr/bin/env bash
# truth.sh — run from the frozen corpus root; prints each question's grep anchor and its hit count.
gt(){ echo "$3 $1:$(grep -nE "$2" "$1" | head -1 | cut -d: -f1) n=$(grep -cE "$2" "$1")"; }
gt scripts/handoff-fire.sh '^probe_account\(\)' probe_account
gt hooks/lib/read-before-write-parity.sh '^RBW_ENFORCED_MODELS=' RBW
gt hooks/model-permission-decider.py '^DEADLINE_S =' DEADLINE
gt bin/cc-token-ledger '^CR_DEFAULT' CR_DEFAULT
gt scripts/claude-lint-models.sh '_prior\$' stale
gt bin/claude-bump-models 'for family in' bumploop
gt bin/cc-recover-safeguard 'FALLBACK_MODELS=' fallback
gt scripts/research-kit/router.py 'def haiku_model' haiku_model
gt scripts/headless-precondition-probe.sh '^TIMEOUT_S=' timeout
gt scripts/lib/detach.sh '^detach\(\)' detach
gt tests/read-before-write-parity.bats 'a model IN the binary' rbwtest
gt bin/claude-accounts '^LOG_PATH =' logpath
gt bin/claude-accounts '^WIRE_NEAR_WALL' wirenear
gt scripts/research-kit/router.py 'shutil.which\("claude"\)' shutil
gt tests/rig/lr-recon-canary.sh '^KITTEN=' kitten
gt bin/cc-token-ledger 'def base_model' base_model
