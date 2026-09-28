#!/bin/bash
# Source this before importing TrueMemory (do not execute): . sandbox-env.sh
# Also export TRUEMEMORY_INGEST_LOCK inside the sandbox; ingest/pipeline.py resolves Path.home() at import.
export HOME=/tmp/tm-sandbox/home
export XDG_CONFIG_HOME=/tmp/tm-sandbox/xdg/config
export XDG_DATA_HOME=/tmp/tm-sandbox/xdg/data
export XDG_CACHE_HOME=/tmp/tm-sandbox/xdg/cache
export XDG_STATE_HOME=/tmp/tm-sandbox/xdg/state
export UV_CACHE_DIR=/tmp/tm-sandbox/uvcache
export HF_HOME=/tmp/tm-sandbox/xdg/cache/huggingface
export HF_HUB_DISABLE_TELEMETRY=1
export TRUEMEMORY_TELEMETRY=off
export TRUEMEMORY_NO_MODEL_SERVER=1
export TRUEMEMORY_DEVICE=cpu
export TRUEMEMORY_EMBED_MODEL=edge
export TRUEMEMORY_DB_PATH=/tmp/tm-sandbox/db/memories.db
export TOKENIZERS_PARALLELISM=false
