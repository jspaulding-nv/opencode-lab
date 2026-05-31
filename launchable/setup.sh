#!/bin/bash
set -euo pipefail

# NVIDIA Brev VM Mode setup script for code-server.
# In the Brev Launchable networking step, expose CODE_SERVER_PORT as a Secure Link
# or TCP port. The default is 8080.

INSTALL_OPENCODE="${INSTALL_OPENCODE:-1}"
OPENCODE_DEFAULT_MODEL="${OPENCODE_DEFAULT_MODEL:-opencode/nemotron-3-super-free}"
OPENCODE_INSTALL_URL="${OPENCODE_INSTALL_URL:-https://opencode.ai/install}"
CODE_SERVER_PORT="${CODE_SERVER_PORT:-8080}"
CODE_SERVER_BIND_ADDR="${CODE_SERVER_BIND_ADDR:-0.0.0.0:${CODE_SERVER_PORT}}"
CODE_SERVER_AUTH="${CODE_SERVER_AUTH:-none}"
CODE_SERVER_USER="${CODE_SERVER_USER:-}"
CODE_SERVER_WORKSPACE="${CODE_SERVER_WORKSPACE:-}"
CODE_SERVER_SERVICE_NAME="${CODE_SERVER_SERVICE_NAME:-code-server}"

log() {
  printf '\n[%s] %s\n' "$(date -Is)" "$*"
}

run_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    command -v sudo >/dev/null || {
      echo "sudo is required when this script is not run as root." >&2
      exit 1
    }
    sudo "$@"
  fi
}

run_as_target_user() {
  if [[ "$(id -un)" == "$TARGET_USER" ]]; then
    "$@"
  elif [[ "$(id -u)" -eq 0 ]]; then
    runuser -u "$TARGET_USER" -- "$@"
  else
    sudo -u "$TARGET_USER" "$@"
  fi
}

user_exists() {
  getent passwd "$1" >/dev/null
}

detect_target_user() {
  if [[ -n "$CODE_SERVER_USER" ]]; then
    user_exists "$CODE_SERVER_USER" || {
      echo "CODE_SERVER_USER=$CODE_SERVER_USER does not exist." >&2
      exit 1
    }
    printf '%s\n' "$CODE_SERVER_USER"
    return
  fi

  if [[ "$(id -u)" -ne 0 ]]; then
    id -un
    return
  fi

  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER:-}" != "root" ]] && user_exists "$SUDO_USER"; then
    printf '%s\n' "$SUDO_USER"
    return
  fi

  for candidate in nvidia ubuntu coder; do
    if user_exists "$candidate"; then
      printf '%s\n' "$candidate"
      return
    fi
  done

  awk -F: '$3 >= 1000 && $3 < 65534 && $7 !~ /(false|nologin)$/ {print $1; exit}' /etc/passwd
}

TARGET_USER="$(detect_target_user)"
if [[ -z "$TARGET_USER" ]]; then
  echo "Could not detect a non-system user. Set CODE_SERVER_USER and rerun." >&2
  exit 1
fi

TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
TARGET_GROUP="$(id -gn "$TARGET_USER")"
CODE_SERVER_WORKSPACE="${CODE_SERVER_WORKSPACE:-$TARGET_HOME}"
EXPOSE_PORT="${CODE_SERVER_BIND_ADDR##*:}"
CONFIG_HOME_DIR="$TARGET_HOME/.config"
LOCAL_DIR="$TARGET_HOME/.local"
LOCAL_SHARE_DIR="$LOCAL_DIR/share"
CACHE_DIR="$TARGET_HOME/.cache"
CONFIG_DIR="$CONFIG_HOME_DIR/code-server"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
DATA_DIR="$LOCAL_SHARE_DIR/code-server"
EXTENSIONS_DIR="$DATA_DIR/extensions"
USER_SETTINGS_DIR="$DATA_DIR/User"
USER_SETTINGS_FILE="$USER_SETTINGS_DIR/settings.json"
OPENCODE_DATA_DIR="$LOCAL_SHARE_DIR/opencode"
OPENCODE_CONFIG_DIR="$CONFIG_HOME_DIR/opencode"
OPENCODE_CONFIG_FILE="$OPENCODE_CONFIG_DIR/opencode.json"
OPENCODE_BIN_DIR="$TARGET_HOME/.opencode/bin"
OPENCODE_BIN="$OPENCODE_BIN_DIR/opencode"
SERVICE_PATH="$OPENCODE_BIN_DIR:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

case "$CODE_SERVER_AUTH" in
  password | none) ;;
  *)
    echo "CODE_SERVER_AUTH must be either 'password' or 'none'." >&2
    exit 1
    ;;
esac

log "Installing prerequisites"
run_root apt-get update
run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl git jq openssl unzip

log "Preparing user-local directories"
run_root install -d -m 755 -o "$TARGET_USER" -g "$TARGET_GROUP" \
  "$CONFIG_HOME_DIR" \
  "$LOCAL_DIR" \
  "$LOCAL_SHARE_DIR" \
  "$CACHE_DIR" \
  "$OPENCODE_DATA_DIR" \
  "$OPENCODE_CONFIG_DIR"
run_root chown "$TARGET_USER:$TARGET_GROUP" \
  "$CONFIG_HOME_DIR" \
  "$LOCAL_DIR" \
  "$LOCAL_SHARE_DIR" \
  "$CACHE_DIR" \
  "$OPENCODE_DATA_DIR" \
  "$OPENCODE_CONFIG_DIR"

if [[ -d "$TARGET_HOME/.opencode" ]]; then
  run_root chown -R "$TARGET_USER:$TARGET_GROUP" "$TARGET_HOME/.opencode"
fi

if ! command -v code-server >/dev/null 2>&1; then
  log "Installing code-server"
  INSTALL_SCRIPT="$(mktemp)"
  curl -fsSL https://code-server.dev/install.sh -o "$INSTALL_SCRIPT"
  run_root sh "$INSTALL_SCRIPT"
  rm -f "$INSTALL_SCRIPT"
else
  log "code-server is already installed: $(command -v code-server)"
fi

CODE_SERVER_BIN="$(command -v code-server || true)"
if [[ -z "$CODE_SERVER_BIN" && -x /usr/bin/code-server ]]; then
  CODE_SERVER_BIN="/usr/bin/code-server"
fi

if [[ -z "$CODE_SERVER_BIN" ]]; then
  echo "code-server installed, but the executable was not found on PATH." >&2
  exit 1
fi

if [[ "$INSTALL_OPENCODE" == "1" ]]; then
  if [[ -x "$OPENCODE_BIN" ]]; then
    log "OpenCode is already installed: $OPENCODE_BIN"
  else
    log "Installing OpenCode for $TARGET_USER"
    run_as_target_user env HOME="$TARGET_HOME" SHELL=/bin/bash OPENCODE_INSTALL_URL="$OPENCODE_INSTALL_URL" \
      XDG_CONFIG_HOME="$CONFIG_HOME_DIR" XDG_DATA_HOME="$LOCAL_SHARE_DIR" XDG_CACHE_HOME="$CACHE_DIR" \
      bash -c 'set -euo pipefail; curl -fsSL "$OPENCODE_INSTALL_URL" | bash'
  fi

  if [[ -d "$TARGET_HOME/.opencode" ]]; then
    run_root chown -R "$TARGET_USER:$TARGET_GROUP" "$TARGET_HOME/.opencode"
  fi

  run_as_target_user env HOME="$TARGET_HOME" bash -c '
    set -euo pipefail
    profile="$HOME/.bashrc"
    line='\''export PATH="$HOME/.opencode/bin:$PATH"'\''
    touch "$profile"
    grep -qxF "$line" "$profile" || printf "\n%s\n" "$line" >> "$profile"
  '

  log "Writing OpenCode defaults"
  OPENCODE_CONFIG_TMP="$(mktemp)"
  OPENCODE_DEFAULT_CONFIG_TMP="$(mktemp)"
  jq -n --arg model "$OPENCODE_DEFAULT_MODEL" '{
    "$schema": "https://opencode.ai/config.json",
    "model": $model,
    "small_model": $model,
    "agent": {
      "build": {
        "model": $model
      },
      "plan": {
        "model": $model
      }
    }
  }' >"$OPENCODE_DEFAULT_CONFIG_TMP"

  if [[ -s "$OPENCODE_CONFIG_FILE" ]] && jq empty "$OPENCODE_CONFIG_FILE" >/dev/null 2>&1; then
    jq -s '.[0] * .[1]' "$OPENCODE_CONFIG_FILE" "$OPENCODE_DEFAULT_CONFIG_TMP" >"$OPENCODE_CONFIG_TMP"
  else
    cp "$OPENCODE_DEFAULT_CONFIG_TMP" "$OPENCODE_CONFIG_TMP"
  fi

  run_root install -m 644 -o "$TARGET_USER" -g "$TARGET_GROUP" "$OPENCODE_CONFIG_TMP" "$OPENCODE_CONFIG_FILE"
  rm -f "$OPENCODE_CONFIG_TMP" "$OPENCODE_DEFAULT_CONFIG_TMP"
fi

log "Writing code-server configuration for $TARGET_USER"
run_root install -d -m 700 -o "$TARGET_USER" -g "$TARGET_GROUP" "$CONFIG_DIR"
run_root install -d -m 755 -o "$TARGET_USER" -g "$TARGET_GROUP" "$DATA_DIR" "$EXTENSIONS_DIR" "$USER_SETTINGS_DIR"
if [[ ! -d "$CODE_SERVER_WORKSPACE" ]]; then
  run_root install -d -m 755 -o "$TARGET_USER" -g "$TARGET_GROUP" "$CODE_SERVER_WORKSPACE"
fi

EXISTING_PASSWORD=""
if [[ -r "$CONFIG_FILE" ]]; then
  EXISTING_PASSWORD="$(awk -F': *' '$1 == "password" {print $2; exit}' "$CONFIG_FILE" || true)"
fi

if [[ "$CODE_SERVER_AUTH" == "password" ]]; then
  CODE_SERVER_PASSWORD="${CODE_SERVER_PASSWORD:-$EXISTING_PASSWORD}"
  if [[ -z "$CODE_SERVER_PASSWORD" ]]; then
    CODE_SERVER_PASSWORD="$(openssl rand -base64 32 | tr -d '=+/' | cut -c1-24)"
  fi
else
  CODE_SERVER_PASSWORD=""
fi

CONFIG_TMP="$(mktemp)"
{
  printf 'bind-addr: %s\n' "$CODE_SERVER_BIND_ADDR"
  printf 'auth: %s\n' "$CODE_SERVER_AUTH"
  if [[ "$CODE_SERVER_AUTH" == "password" ]]; then
    printf 'password: %s\n' "$CODE_SERVER_PASSWORD"
  fi
  printf 'cert: false\n'
} >"$CONFIG_TMP"

run_root install -m 600 -o "$TARGET_USER" -g "$TARGET_GROUP" "$CONFIG_TMP" "$CONFIG_FILE"
rm -f "$CONFIG_TMP"

log "Writing VS Code Server defaults"
SETTINGS_TMP="$(mktemp)"
DEFAULT_SETTINGS_TMP="$(mktemp)"
cat >"$DEFAULT_SETTINGS_TMP" <<'EOF'
{
  "workbench.colorTheme": "Default Dark Modern",
  "workbench.secondarySideBar.defaultVisibility": "hidden"
}
EOF

if [[ -s "$USER_SETTINGS_FILE" ]] && jq empty "$USER_SETTINGS_FILE" >/dev/null 2>&1; then
  jq -s '.[0] * .[1]' "$USER_SETTINGS_FILE" "$DEFAULT_SETTINGS_TMP" >"$SETTINGS_TMP"
else
  cp "$DEFAULT_SETTINGS_TMP" "$SETTINGS_TMP"
fi

run_root install -m 644 -o "$TARGET_USER" -g "$TARGET_GROUP" "$SETTINGS_TMP" "$USER_SETTINGS_FILE"
rm -f "$SETTINGS_TMP" "$DEFAULT_SETTINGS_TMP"
run_root chown -R "$TARGET_USER:$TARGET_GROUP" "$CONFIG_DIR" "$DATA_DIR" "$OPENCODE_DATA_DIR" "$OPENCODE_CONFIG_DIR"

log "Creating systemd service"
SERVICE_FILE="/etc/systemd/system/${CODE_SERVER_SERVICE_NAME}.service"
SERVICE_TMP="$(mktemp)"
cat >"$SERVICE_TMP" <<EOF
[Unit]
Description=code-server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$TARGET_USER
Group=$TARGET_GROUP
WorkingDirectory=$CODE_SERVER_WORKSPACE
Environment=HOME=$TARGET_HOME
Environment=PATH=$SERVICE_PATH
Environment=XDG_CONFIG_HOME=$CONFIG_HOME_DIR
Environment=XDG_DATA_HOME=$LOCAL_SHARE_DIR
Environment=XDG_CACHE_HOME=$CACHE_DIR
ExecStart=$CODE_SERVER_BIN --config $CONFIG_FILE --user-data-dir $DATA_DIR --extensions-dir $EXTENSIONS_DIR $CODE_SERVER_WORKSPACE
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

run_root install -m 644 "$SERVICE_TMP" "$SERVICE_FILE"
rm -f "$SERVICE_TMP"

if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
  run_root systemctl daemon-reload
  run_root systemctl enable --now "$CODE_SERVER_SERVICE_NAME.service"
  run_root systemctl --no-pager --full status "$CODE_SERVER_SERVICE_NAME.service" || true
else
  log "systemd is unavailable; starting code-server with nohup for this session"
  run_as_target_user env HOME="$TARGET_HOME" PATH="$SERVICE_PATH" \
    XDG_CONFIG_HOME="$CONFIG_HOME_DIR" XDG_DATA_HOME="$LOCAL_SHARE_DIR" XDG_CACHE_HOME="$CACHE_DIR" \
    nohup "$CODE_SERVER_BIN" \
    --config "$CONFIG_FILE" \
    --user-data-dir "$DATA_DIR" \
    --extensions-dir "$EXTENSIONS_DIR" \
    "$CODE_SERVER_WORKSPACE" \
    >"$TARGET_HOME/code-server.log" 2>&1 &
fi

cat <<EOF

code-server setup complete.

User:      $TARGET_USER
Workspace: $CODE_SERVER_WORKSPACE
URL:       http://localhost:$EXPOSE_PORT
Auth:      $CODE_SERVER_AUTH
EOF

if [[ "$CODE_SERVER_AUTH" == "password" ]]; then
  cat <<EOF
Password:  $CODE_SERVER_PASSWORD
EOF
fi

if [[ "$INSTALL_OPENCODE" == "1" ]]; then
  OPENCODE_VERSION="$(run_as_target_user env HOME="$TARGET_HOME" PATH="$SERVICE_PATH" XDG_CONFIG_HOME="$CONFIG_HOME_DIR" XDG_DATA_HOME="$LOCAL_SHARE_DIR" XDG_CACHE_HOME="$CACHE_DIR" bash -c 'opencode --version' 2>/dev/null || true)"
  if [[ -n "$OPENCODE_VERSION" ]]; then
    cat <<EOF
OpenCode:  $OPENCODE_VERSION
EOF
  else
    cat <<EOF
OpenCode:  installed at $OPENCODE_BIN
EOF
  fi
  cat <<EOF
Default model: $OPENCODE_DEFAULT_MODEL
EOF
fi

cat <<EOF

Brev Launchable networking:
  Expose port $EXPOSE_PORT as a Secure Link or TCP port.

Override examples:
  CODE_SERVER_PORT=9090 ./launchable/setup.sh
  CODE_SERVER_PASSWORD='choose-a-password' ./launchable/setup.sh
  CODE_SERVER_AUTH=password ./launchable/setup.sh
  OPENCODE_DEFAULT_MODEL=opencode/gpt-5.5 ./launchable/setup.sh
  INSTALL_OPENCODE=0 ./launchable/setup.sh
EOF
