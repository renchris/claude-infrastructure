---
name: agent-browser
description: Automates browser interactions for web testing, form filling, screenshots, and data extraction. Use when the user needs to navigate websites, interact with web pages, fill forms, take screenshots, test web applications, or extract information from web pages. Use this instead of BrowserMCP when MCP tools are unavailable.
allowed-tools: Bash
---

# agent-browser

Headless browser automation CLI. Uses bundled Chromium (not existing Chrome sessions).

## Quick Start

```bash
agent-browser open <url>        # Navigate
agent-browser snapshot -i       # Get interactive elements with refs
agent-browser click @e1         # Click by ref
agent-browser fill @e2 "text"   # Fill input by ref
agent-browser close             # Close browser
```

## Core Workflow

1. **Navigate**: `agent-browser open https://example.com`
2. **Snapshot**: `agent-browser snapshot -i` - Get element refs (@e1, @e2, etc.)
3. **Interact**: Use refs from snapshot
   - `agent-browser click @e3`
   - `agent-browser fill @e4 "input text"`
4. **Re-snapshot** after page changes

## Common Commands

### Navigation
```bash
agent-browser open <url>       # Navigate to URL
agent-browser back             # Go back
agent-browser forward          # Go forward
agent-browser reload           # Reload page
agent-browser close            # Close browser
```

### Snapshot Options
```bash
agent-browser snapshot         # Full accessibility tree
agent-browser snapshot -i      # Interactive elements only (recommended)
agent-browser snapshot -c      # Compact (remove empty elements)
agent-browser snapshot -d 3    # Limit depth to 3 levels
agent-browser snapshot --json  # Machine-readable output
```

### Interactions
```bash
agent-browser click @e1        # Click element
agent-browser fill @e2 "text"  # Clear and fill input
agent-browser type @e3 "text"  # Type without clearing
agent-browser hover @e4        # Hover over element
agent-browser check @e5        # Check checkbox
agent-browser uncheck @e6      # Uncheck checkbox
agent-browser select @e7 "val" # Select dropdown option
agent-browser press Enter      # Press key
```

### Get Information
```bash
agent-browser get text @e1     # Get element text
agent-browser get value @e2    # Get input value
agent-browser get title        # Get page title
agent-browser get url          # Get current URL
```

### Screenshots
```bash
agent-browser screenshot              # Screenshot to stdout
agent-browser screenshot page.png     # Save to file
agent-browser screenshot -f page.png  # Full page screenshot
```

### Waiting
```bash
agent-browser wait @e1                # Wait for element visible
agent-browser wait 2000               # Wait 2 seconds
agent-browser wait --text "Welcome"   # Wait for text
agent-browser wait --load networkidle # Wait for network idle
```

## Sessions (Isolated Instances)

```bash
agent-browser --session test1 open site-a.com
agent-browser --session test2 open site-b.com
agent-browser session list     # List active sessions
```

## Debug Mode

```bash
agent-browser open <url> --headed  # Show browser window
agent-browser console              # View console logs
agent-browser errors               # View page errors
```

## CDP Mode (Connect to Existing Browser)

Connect to existing browsers (Dia, Chrome, Electron) via Chrome DevTools Protocol:

```bash
# Start browser with remote debugging enabled:
# - Dia Browser: Enable in settings or launch with --remote-debugging-port=9222
# - Chrome: google-chrome --remote-debugging-port=9222
# - Chromium: chromium --remote-debugging-port=9222

# Connect via CDP
agent-browser --cdp 9222 snapshot -i      # Snapshot existing page
agent-browser --cdp 9222 click @e1        # Interact with existing session
agent-browser --cdp 9222 get url          # Get current URL
```

**Use CDP mode when:**
- Need access to logged-in sessions (cookies, auth state)
- Automating Electron apps
- BrowserMCP unavailable but need existing browser control

## Example: Login Flow

```bash
agent-browser open https://app.example.com/login
agent-browser snapshot -i
# Output shows: textbox "Email" [@e3], textbox "Password" [@e4], button "Sign In" [@e5]
agent-browser fill @e3 "user@example.com"
agent-browser fill @e4 "password123"
agent-browser click @e5
agent-browser wait --load networkidle
agent-browser snapshot -i  # Verify login success
```
