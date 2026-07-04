#!/bin/sh

set -u

provider="${1:-}"
state="${2:-}"
event="${3:-unknown}"

case "$provider" in
  codex|claude) ;;
  *) exit 0 ;;
esac

case "$state" in
  running|waiting|completed|error) ;;
  *) exit 0 ;;
esac

if [ -z "${RURI_TERMINAL_TAB_ID:-}" ] || [ -z "${RURI_AGENT_STATUS_DIR:-}" ]; then
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  exit 0
fi

payload=""
if [ ! -t 0 ]; then
  payload=$(cat 2>/dev/null || true)
fi

mkdir -p "$RURI_AGENT_STATUS_DIR" 2>/dev/null || exit 0

export RURI_AGENT_PROVIDER="$provider"
export RURI_AGENT_STATE="$state"
export RURI_AGENT_EVENT="$event"
export RURI_AGENT_HOOK_PAYLOAD="$payload"

python3 - <<'PY'
import datetime
import json
import os
import re
import tempfile

terminal_id = os.environ.get("RURI_TERMINAL_TAB_ID", "")
status_dir = os.environ.get("RURI_AGENT_STATUS_DIR", "")

if not re.fullmatch(r"[0-9A-Fa-f-]{36}", terminal_id) or not status_dir:
    raise SystemExit(0)

try:
    hook_payload = json.loads(os.environ.get("RURI_AGENT_HOOK_PAYLOAD", ""))
except ValueError:
    hook_payload = {}
if not isinstance(hook_payload, dict):
    hook_payload = {}

# Status files must track the main agent only: Claude Code re-fires configured
# Stop hooks as SubagentStop whenever a subagent finishes, which would otherwise
# spam "completed" notifications. Subagent permission waits still need the user,
# so "waiting" passes through.
is_subagent_context = (
    bool(hook_payload.get("agent_id"))
    or hook_payload.get("hook_event_name") == "SubagentStop"
)
if is_subagent_context and os.environ.get("RURI_AGENT_STATE") != "waiting":
    raise SystemExit(0)

# A main-agent Stop that leaves background subagents running is not a real
# completion; the session resumes when they finish and a later Stop reports
# background_tasks empty. Background shells are excluded: persistent ones
# (e.g. dev servers) never exit, which would suppress completion forever.
if not is_subagent_context and os.environ.get("RURI_AGENT_STATE") == "completed":
    background_tasks = hook_payload.get("background_tasks")
    has_running_subagent = isinstance(background_tasks, list) and any(
        isinstance(task, dict)
        and task.get("type") == "subagent"
        and task.get("status") == "running"
        for task in background_tasks
    )
    if has_running_subagent:
        raise SystemExit(0)

document = {
    "version": 1,
    "terminalID": terminal_id,
    "provider": os.environ.get("RURI_AGENT_PROVIDER", ""),
    "state": os.environ.get("RURI_AGENT_STATE", ""),
    "event": os.environ.get("RURI_AGENT_EVENT", "unknown"),
    "updatedAt": datetime.datetime.now(datetime.timezone.utc)
        .isoformat(timespec="milliseconds")
        .replace("+00:00", "Z"),
    "workspaceRoot": os.environ.get("RURI_WORKTREE_ROOT") or None,
}

target = os.path.join(status_dir, f"{terminal_id}.json")
fd, temporary_path = tempfile.mkstemp(
    prefix=f".{terminal_id}.",
    suffix=".tmp",
    dir=status_dir,
    text=True,
)

try:
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(document, handle, indent=2, sort_keys=True)
        handle.write("\n")
    os.replace(temporary_path, target)
except Exception:
    try:
        os.unlink(temporary_path)
    except OSError:
        pass
    raise SystemExit(0)
PY
