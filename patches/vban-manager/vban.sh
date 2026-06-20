#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${SCRIPT_DIR}"

usage() {
  echo "Usage: $0 {start|args|remove|stop|status|is-active|plugin|start-service} <id> [args...]"
}

require_id() {
  if [[ $# -lt 1 || -z "${1:-}" ]]; then
    usage >&2
    exit 2
  fi
}

ensure_session_env() {
  local uid
  uid="$(id -u)"
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/${uid}}"
  export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"
  export PULSE_SERVER="${PULSE_SERVER:-unix:${XDG_RUNTIME_DIR}/pulse/native}"
  export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
}

ensure_pipewire() {
  ensure_session_env
  systemctl --user start pipewire.socket pipewire.service 2>/dev/null || true
  systemctl --user start pipewire-pulse.socket pipewire-pulse.service 2>/dev/null || true
  systemctl --user start wireplumber.service 2>/dev/null || true
}

resolve_vban_cmd() {
  local mode="$1"
  local candidate="vban_${mode}"
  local resolved=""

  resolved="$(command -v "${candidate}" 2>/dev/null || true)"
  if [[ -n "${resolved}" ]]; then
    printf '%s\n' "${resolved}"
    return 0
  fi

  for path in /usr/local/bin "/usr/local/bin/${candidate}" /usr/bin "/usr/bin/${candidate}"; do
    if [[ -x "${path}" ]]; then
      printf '%s\n' "${path}"
      return 0
    fi
  done

  return 1
}

case "${1:-}" in
  start)
    require_id "${2:-}"
    ensure_session_env
    systemctl --user start "vban@${2}.service"
    ;;

  start-service)
    require_id "${2:-}"
    args_file="args-${2}.txt"
    log_file="vban-${2}.log"
    if [[ ! -f "${args_file}" ]]; then
      echo "Missing ${args_file}" >&2
      exit 1
    fi

    ensure_pipewire
    read -r args < "${args_file}"

    mapfile -t argv < <(python3 - "${args_file}" <<'PY'
import shlex
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    line = handle.read().strip()
argv = shlex.split(line)
for item in argv:
    print(item)
PY
)

    if [[ ${#argv[@]} -lt 1 ]]; then
      echo "No VBAN mode in ${args_file}" >&2
      exit 1
    fi

    if ! cmd="$(resolve_vban_cmd "${argv[0]}")"; then
      echo "Could not find vban_${argv[0]} in PATH (/usr/local/bin). Reinstall vban." >&2 | tee -a "${log_file}"
      exit 127
    fi

    {
      echo "=== $(date -Is) start vban@${2} ==="
      echo "user=$(whoami) uid=$(id -u)"
      echo "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}"
      echo "PULSE_SERVER=${PULSE_SERVER}"
      echo "cmd=${cmd}"
      printf 'args='
      printf '%q ' "${argv[@]:1}"
      echo
    } >> "${log_file}"

    exec "${cmd}" "${argv[@]:1}" >> "${log_file}" 2>&1
    ;;

  args)
    require_id "${2:-}"
    id="${2}"
    shift 2
    printf '%s\n' "$*" > "args-${id}.txt"
    ;;

  remove)
    require_id "${2:-}"
    systemctl --user stop "vban@${2}.service" || true
    rm -f "args-${2}.txt" "vban-${2}.log"
    ;;

  stop)
    require_id "${2:-}"
    systemctl --user stop "vban@${2}.service"
    ;;

  status)
    require_id "${2:-}"
    ensure_session_env
    systemctl --user status "vban@${2}.service" -l --no-pager || true
    ;;

  is-active)
    require_id "${2:-}"
    ensure_session_env
    systemctl --user is-active "vban@${2}.service" || true
    ;;

  plugin)
    require_id "${2:-}"
    plugin="${2}"
    shift 2
    cd "${SCRIPT_DIR}/../plugins/${plugin}"
    bash "${plugin}.sh" "$@"
    ;;

  *)
    usage >&2
    exit 2
    ;;
esac
