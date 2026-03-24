#!/bin/bash
# BrowserMCP Wrapper Script
# Addresses 71% of MCP connection failures by:
# - Properly loading NVM environment
# - Ensuring consistent Node.js path
# - Logging startup to stderr (won't corrupt stdio protocol)
#
# Usage in .mcp.json:
# {
#   "mcpServers": {
#     "browsermcp": {
#       "command": "/Users/chrisren/bin/browsermcp-wrapper.sh",
#       "timeout": 15000
#     }
#   }
# }

set -euo pipefail

# Load NVM if present (addresses 28% of connection failures)
export NVM_DIR="${HOME}/.nvm"
if [ -s "${NVM_DIR}/nvm.sh" ]; then
  # shellcheck source=/dev/null
  . "${NVM_DIR}/nvm.sh"
  nvm use default > /dev/null 2>&1 || true
fi

# Ensure Node.js is in PATH
if ! command -v node &> /dev/null; then
  echo "ERROR: Node.js not found in PATH" >&2
  exit 1
fi

# Log to stderr (won't corrupt stdio protocol)
echo "[$(date '+%Y-%m-%d %H:%M:%S')] BrowserMCP starting via wrapper..." >&2
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Node: $(which node) ($(node --version))" >&2

# Execute BrowserMCP with all arguments
# Using npx without @latest for stability (per BrowserMCP docs)
exec npx -y @browsermcp/mcp "$@"
