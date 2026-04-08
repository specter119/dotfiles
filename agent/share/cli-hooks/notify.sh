#!/bin/bash

# Coding CLI Hook Notifier (Universal)
# Sends system notifications when user confirmation is needed
# Supports WSL and Linux environments with customizable click actions

set -e

# Function to detect CLI name from parent process
detect_cli_name() {
	local parent_cmd
	parent_cmd=$(ps -o comm= -p $PPID 2>/dev/null || echo "")
	case "$parent_cmd" in
	*claude*) echo "Claude Code" ;;
	*codex*) echo "Codex" ;;
	*amp*) echo "AMP" ;;
	*opencode*) echo "OpenCode" ;;
	*) echo "Coding CLI" ;;
	esac
}

# Format Codex legacy notify payload into a readable notification message.
format_codex_notify_payload() {
	local payload="$1"

	python3 - "$payload" <<'PY'
import json
import os
import sys


def compact(value: str, limit: int) -> str:
    normalized = " ".join(value.split())
    if len(normalized) <= limit:
        return normalized
    return normalized[: limit - 3] + "..."


try:
    data = json.loads(sys.argv[1])
except Exception:
    sys.exit(1)

if data.get("type") != "agent-turn-complete":
    sys.exit(1)

message = (data.get("last_assistant_message") or "").strip()
if message:
    print(compact(message, 180))
    sys.exit(0)

cwd = data.get("cwd") or ""
workspace = os.path.basename(cwd.rstrip("/")) or cwd or "workspace"
inputs = [str(item).strip() for item in data.get("input_messages") or [] if str(item).strip()]

if inputs:
    prompt = compact(" ".join(inputs), 120)
    print(f"Turn complete in {workspace}: {prompt}")
else:
    print(f"Agent turn complete in {workspace}")
PY
}

# Configuration
NOTIFICATION_TITLE="${NOTIFICATION_TITLE:-$(detect_cli_name)}"
NOTIFICATION_ICON="dialog-information"
NOTIFICATION_TIMEOUT=5000 # 5 seconds for Linux
CLICK_ACTION="${CLICK_ACTION:-}"

# Function to detect environment
detect_environment() {
	if grep -qi "microsoft\|wsl" /proc/version 2>/dev/null; then
		echo "wsl"
	elif [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; then
		echo "linux"
	else
		echo "unknown"
	fi
}

escape_powershell_string() {
	printf "%s" "$1" | sed "s/'/''/g"
}

# Function to send WSL notification
send_wsl_notification() {
	local message="$1"
	local action_cmd="$2"
	local escaped_title
	local escaped_message
	local escaped_action

	escaped_title=$(escape_powershell_string "$NOTIFICATION_TITLE")
	escaped_message=$(escape_powershell_string "$message")
	escaped_action=$(escape_powershell_string "$action_cmd")

	if ! command -v powershell.exe >/dev/null 2>&1; then
		echo "PowerShell not available. Make sure you're running in WSL with Windows PowerShell accessible." >&2
		return 1
	fi

	# Create PowerShell command for notification
	local ps_cmd="
        Add-Type -AssemblyName System.Windows.Forms;
        \$notification = New-Object System.Windows.Forms.NotifyIcon;
        \$notification.Icon = [System.Drawing.SystemIcons]::Information;
        \$notification.BalloonTipTitle = '$escaped_title';
        \$notification.BalloonTipText = '$escaped_message';
        \$notification.Visible = \$true;
    "

	# Add click handler if action is provided
	if [ -n "$action_cmd" ]; then
		ps_cmd+="
        \$notification.Add_BalloonTipClicked({
            Start-Process powershell -ArgumentList '-Command', '$escaped_action' -WindowStyle Hidden
        });
        "
	fi

	ps_cmd+="
        \$notification.ShowBalloonTip(10000);
        Start-Sleep -Seconds 1;
        \$notification.Dispose();
    "

	# Execute notification
	powershell.exe -Command "$ps_cmd" 2>/dev/null &

	echo "WSL notification sent to Windows host"
}

# Function to send Linux notification
send_linux_notification() {
	local message="$1"
	local action_cmd="$2"

	# Check if we're in a graphical environment
	if [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ]; then
		echo "No graphical environment detected" >&2
		return 1
	fi

	if ! command -v notify-send >/dev/null 2>&1; then
		echo "notify-send not available. Please install libnotify-bin" >&2
		return 1
	fi

	# Send notification
	if [ -n "$action_cmd" ]; then
		# Try to send with action if supported
		if notify-send --help 2>&1 | grep -q "action"; then
			notify-send \
				--app-name="$NOTIFICATION_TITLE" \
				--icon="$NOTIFICATION_ICON" \
				--expire-time="$NOTIFICATION_TIMEOUT" \
				--action="click=Click to execute: $action_cmd" \
				"$NOTIFICATION_TITLE" \
				"$message" &

			# Simple action handler
			if command -v gdbus >/dev/null 2>&1; then
				(timeout 30 gdbus monitor --session --dest org.freedesktop.Notifications 2>/dev/null |
					while read -r line; do
						if echo "$line" | grep -q "ActionInvoked.*click"; then
							eval "$action_cmd" &
							break
						fi
					done) &
			fi
		else
			# Fallback: basic notification
			notify-send \
				--app-name="$NOTIFICATION_TITLE" \
				--icon="$NOTIFICATION_ICON" \
				--expire-time="$NOTIFICATION_TIMEOUT" \
				"$NOTIFICATION_TITLE" \
				"$message (Click action: $action_cmd)" &
		fi
	else
		# Simple notification without action
		notify-send \
			--app-name="$NOTIFICATION_TITLE" \
			--icon="$NOTIFICATION_ICON" \
			--expire-time="$NOTIFICATION_TIMEOUT" \
			"$NOTIFICATION_TITLE" \
			"$message" &
	fi

	echo "Linux notification sent"
}

# Main function
main() {
	local message="${1:-}"
	local action="${2:-$CLICK_ACTION}"

	if [ -n "$message" ]; then
		local formatted_message
		if formatted_message=$(format_codex_notify_payload "$message" 2>/dev/null); then
			message="$formatted_message"
		fi
	fi

	if [ -z "$message" ]; then
		message="User confirmation needed in $NOTIFICATION_TITLE"
	fi

	local env_type
	env_type=$(detect_environment)

	case "$env_type" in
	"wsl")
		send_wsl_notification "$message" "$action"
		;;
	"linux")
		send_linux_notification "$message" "$action"
		;;
	*)
		echo "Unsupported environment. This script requires WSL or Linux with GUI." >&2
		exit 1
		;;
	esac
}

# Help function
show_help() {
	cat <<EOF
Coding CLI Hook Notifier (Universal)

Usage: $0 [MESSAGE] [CLICK_ACTION]

Arguments:
  MESSAGE       Optional custom message or Codex notify JSON payload
  CLICK_ACTION  Optional command to run when notification is clicked

Environment Variables:
  NOTIFICATION_TITLE   Override auto-detected CLI name
  CLICK_ACTION         Command to run when notification is clicked

Environment Support:
  - WSL: Uses Windows toast notifications via PowerShell
  - Linux: Uses notify-send with D-Bus action handling

Dependencies:
  WSL: Windows PowerShell accessible from WSL
  Linux: notify-send (libnotify-bin), X11/Wayland display server

Examples:
  $0
  $0 "Please review the changes"
  $0 '{"type":"agent-turn-complete","cwd":"/tmp/demo","input_messages":["Fix tests"],"last_assistant_message":"Done."}'
  $0 "Waiting for input" "gnome-terminal"
  $0 "Task complete" "wt.exe"

Setting custom title:
  export NOTIFICATION_TITLE="My CLI"

CLI Hook Integration:
  Add to your CLI's hook configuration:
  {
    "hooks": {
      "before_user_input": "./claude-hook-notifier.sh 'Waiting for input'"
    }
  }
EOF
}

# Parse arguments
case "${1:-}" in
-h | --help)
	show_help
	exit 0
	;;
*)
	main "$@"
	;;
esac
