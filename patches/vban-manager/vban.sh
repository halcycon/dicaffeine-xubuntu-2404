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

case "${1:-}" in
  start)
    require_id "${2:-}"
    systemctl --user start "vban@${2}.service"
    ;;

  start-service)
    require_id "${2:-}"
    args_file="args-${2}.txt"
    if [[ ! -f "${args_file}" ]]; then
      echo "Missing ${args_file}" >&2
      exit 1
    fi
    read -r args < "${args_file}"
    echo "Started as user: $(whoami)"
    echo "vban_${args}"

    # VBAN-manager stores arguments as a simple space-delimited line, e.g.:
    #   receptor -i 192.168.1.10 -p 6980 -s Stream1 -b pulseaudio -d VBAN
    # This deliberately does not support spaces inside stream/device names.
    read -r -a argv <<< "${args}"
    if [[ ${#argv[@]} -lt 1 ]]; then
      echo "No VBAN mode in ${args_file}" >&2
      exit 1
    fi
    cmd="vban_${argv[0]}"
    exec "${cmd}" "${argv[@]:1}"
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
    rm -f "args-${2}.txt"
    ;;

  stop)
    require_id "${2:-}"
    systemctl --user stop "vban@${2}.service"
    ;;

  status)
    require_id "${2:-}"
    systemctl --user status "vban@${2}.service" -l --no-pager || true
    ;;

  is-active)
    require_id "${2:-}"
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
