#!/usr/bin/env bash
# Ensure the kit lives at the canonical path (/opt/wyse-ndi-kit by default).
# Called from install-wyse-ndi.sh before other work.

set -euo pipefail

CONFIG_FILE="/etc/default/wyse-ndi-kit"
DEFAULT_CANONICAL="/opt/wyse-ndi-kit"

usage() {
  echo "Usage: $0 [--print-canonical|--migrate] [source_dir]" >&2
}

load_config() {
  CANONICAL="$DEFAULT_CANONICAL"
  GIT_REMOTE=""
  GIT_BRANCH=""
  TARGET_USER="${SUDO_USER:-${TARGET_USER:-ndi}}"

  if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    . "$CONFIG_FILE" || true
  fi

  CANONICAL="${WYSE_NDI_KIT_DIR:-$CANONICAL}"
  GIT_REMOTE="${WYSE_NDI_KIT_GIT_REMOTE:-}"
  GIT_BRANCH="${WYSE_NDI_KIT_GIT_BRANCH:-}"
  TARGET_USER="${WYSE_NDI_KIT_AUTO_UPDATE_USER:-${SUDO_USER:-${TARGET_USER:-ndi}}}"
}

resolve_path() {
  local path="$1"
  if [ -d "$path" ]; then
    (cd "$path" && pwd -P)
  else
    printf '%s\n' "$path"
  fi
}

detect_git_remote() {
  local dir="$1"
  if [ -d "$dir/.git" ]; then
    git -C "$dir" remote get-url origin 2>/dev/null || true
  fi
}

detect_git_branch() {
  local dir="$1"
  local branch=""
  if [ -n "$GIT_BRANCH" ]; then
    printf '%s\n' "$GIT_BRANCH"
    return 0
  fi
  branch="$(git -C "$dir" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || true)"
  if [ -n "$branch" ]; then
    printf '%s\n' "$branch"
    return 0
  fi
  branch="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [ -n "$branch" ] && [ "$branch" != "HEAD" ]; then
    printf '%s\n' "$branch"
    return 0
  fi
  printf '%s\n' "main"
}

cleanup_junk_files() {
  local dir="$1"
  if [ -x /usr/local/bin/wyse-ndi-kit-cleanup-junk ]; then
    /usr/local/bin/wyse-ndi-kit-cleanup-junk "$dir" || true
    return 0
  fi
  local script_dir
  script_dir="$(cd "$(dirname "$0")/.." && pwd)"
  if [ -x "${script_dir}/bin/wyse-ndi-kit-cleanup-junk" ]; then
    "${script_dir}/bin/wyse-ndi-kit-cleanup-junk" "$dir" || true
  fi
}

write_config_stub() {
  local remote="$1"
  local branch="$2"

  if [ -f "$CONFIG_FILE" ]; then
    return 0
  fi

  echo "Installing ${CONFIG_FILE}"
  sudo install -d -m 0755 "$(dirname "$CONFIG_FILE")"
  sudo tee "$CONFIG_FILE" >/dev/null <<EOF
# Wyse NDI kit — created by wyse-ndi-kit-ensure-path
WYSE_NDI_KIT_DIR=${CANONICAL}
WYSE_NDI_KIT_GIT_REMOTE=${remote}
WYSE_NDI_KIT_GIT_BRANCH=${branch}
WYSE_NDI_KIT_AUTO_UPDATE_USER=${TARGET_USER}
WYSE_NDI_KIT_AUTO_UPDATE=1
WYSE_NDI_KIT_AUTO_UPDATE_BOOT_DELAY_SEC=180
WYSE_NDI_KIT_AUTO_UPDATE_RANDOM_DELAY_SEC=120
EOF
  sudo chmod 0644 "$CONFIG_FILE"
}

migrate_to_canonical() {
  local source="$1"
  local canonical_resolved
  canonical_resolved="$(resolve_path "$CANONICAL")"

  if [ -d "$canonical_resolved/.git" ] || [ -f "$canonical_resolved/install-wyse-ndi.sh" ]; then
    echo "Canonical kit already present at ${CANONICAL}"
    cleanup_junk_files "$canonical_resolved"
    return 0
  fi

  local remote branch
  remote="${GIT_REMOTE:-$(detect_git_remote "$source")}"
  branch="$(detect_git_branch "$source")"

  echo "Installing kit to ${CANONICAL}"

  if [ -n "$remote" ]; then
    sudo mkdir -p "$(dirname "$CANONICAL")"
    echo "Cloning ${remote} (branch ${branch}) into ${CANONICAL}"
    if [ -e "$CANONICAL" ]; then
      sudo rm -rf "$CANONICAL"
    fi
    if ! sudo -u "$TARGET_USER" git clone --branch "$branch" "$remote" "$CANONICAL" 2>/dev/null; then
      echo "Branch ${branch} clone failed; trying default branch..."
      sudo -u "$TARGET_USER" git clone "$remote" "$CANONICAL"
    fi
  elif [ -d "$source/.git" ] || [ -f "$source/install-wyse-ndi.sh" ]; then
    sudo mkdir -p "$(dirname "$CANONICAL")"
    echo "No git remote configured; copying from ${source} (rsync)"
    sudo rsync -a \
      --exclude 'Accept:' \
      --exclude 'Host:' \
      --exclude 'User-Agent:' \
      --exclude 'GET' \
      --exclude 'POST' \
      "$source/" "$CANONICAL/"
    sudo chown -R "$TARGET_USER:$TARGET_USER" "$CANONICAL"
  else
    echo "ERROR: cannot migrate ${source} — not a kit checkout and no git remote configured." >&2
    exit 1
  fi

  cleanup_junk_files "$CANONICAL"
  write_config_stub "$remote" "$branch"
}

ACTION="migrate"
SOURCE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --print-canonical)
      ACTION="print"
      shift
      ;;
    --migrate)
      ACTION="migrate"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      SOURCE="$1"
      shift
      ;;
  esac
done

if [ -z "$SOURCE" ]; then
  SOURCE="$(cd "$(dirname "$0")/.." && pwd)"
fi

load_config

SOURCE_RESOLVED="$(resolve_path "$SOURCE")"
CANONICAL_RESOLVED="$(resolve_path "$CANONICAL")"

if [ "$ACTION" = "print" ]; then
  printf '%s\n' "$CANONICAL_RESOLVED"
  exit 0
fi

if [ "$SOURCE_RESOLVED" = "$CANONICAL_RESOLVED" ]; then
  write_config_stub "$(detect_git_remote "$SOURCE_RESOLVED")" "$(detect_git_branch "$SOURCE_RESOLVED")"
  cleanup_junk_files "$CANONICAL_RESOLVED"
  exit 0
fi

if [ ! -d "$CANONICAL_RESOLVED" ] || [ ! -f "$CANONICAL_RESOLVED/install-wyse-ndi.sh" ]; then
  migrate_to_canonical "$SOURCE_RESOLVED"
  CANONICAL_RESOLVED="$(resolve_path "$CANONICAL")"
fi

if [ "$SOURCE_RESOLVED" != "$CANONICAL_RESOLVED" ]; then
  echo "Kit canonical path: ${CANONICAL}"
  echo "Re-run installs from ${CANONICAL} (not ${SOURCE})."
fi
