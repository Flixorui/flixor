#!/bin/sh
# Installs or updates the Flixor server (the web app and its backend) on macOS or Linux.
#
#   curl -fsSL https://raw.githubusercontent.com/Flixorui/flixor/main/install.sh | sh
#
# Options go after `sh -s --`, for example:
#
#   curl -fsSL https://raw.githubusercontent.com/Flixorui/flixor/main/install.sh | sh -s -- --port 8080
#
#   --version <tag>    Install this release instead of the newest (e.g. server-v1.0.0)
#   --port <n>         Port to serve on (default 3001)
#   --bin-dir <dir>    Where to put flixor-server (default ~/.local/bin; /usr/local/bin as root)
#   --data-dir <dir>   Data folder (default ~/.flixor; /var/lib/flixor as root)
#   --no-service       Don't set up or start a background service
#   --no-ffmpeg        Don't install FFmpeg if it is missing
#   --uninstall        Remove the server and its service (keeps the data folder)
#   --purge            With --uninstall, also delete the data folder
#   --help             Show this help
#
# Running it again updates to the newest release. Everything happens inside main(),
# called on the last line, so a partly downloaded script never runs.

set -eu

REPO="Flixorui/flixor"
# FLIXOR_SERVICE_NAME is for tests that must not touch a real install.
SERVICE_NAME="${FLIXOR_SERVICE_NAME:-flixor}"
if [ "$SERVICE_NAME" = flixor ]; then LAUNCHD_LABEL=xyz.flixor.server; else LAUNCHD_LABEL="xyz.flixor.$SERVICE_NAME"; fi

say() { printf '%s\n' "$*"; }
step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<EOF
Installs or updates the Flixor server (the web app and its backend).

  curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | sh -s -- [options]

  --version <tag>    Install this release instead of the newest (e.g. server-v1.0.0)
  --port <n>         Port to serve on (default 3001)
  --bin-dir <dir>    Where to put flixor-server (default ~/.local/bin; /usr/local/bin as root)
  --data-dir <dir>   Data folder (default ~/.flixor; /var/lib/flixor as root)
  --no-service       Don't set up or start a background service
  --no-ffmpeg        Don't install FFmpeg if it is missing
  --uninstall        Remove the server and its service (keeps the data folder)
  --purge            With --uninstall, also delete the data folder
  --help             Show this help
EOF
}

# Runs a command as root: directly when already root, otherwise through sudo.
as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif have sudo; then
    sudo "$@"
  else
    return 1
  fi
}

fetch() { # url dest
  if have curl; then
    curl -fsSL --retry 3 -o "$2" "$1"
  elif have wget; then
    wget -q -O "$2" "$1"
  else
    die "curl or wget is needed"
  fi
}

fetch_text() { # url
  if have curl; then
    curl -fsSL --retry 3 "$1"
  else
    wget -q -O - "$1"
  fi
}

sha256() { # file
  if have sha256sum; then
    sha256sum "$1" | awk '{print $1}'
  elif have shasum; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    die "sha256sum or shasum is needed to verify the download"
  fi
}

detect_target() {
  case "$(uname -s)" in
    Darwin) os=darwin ;;
    Linux) os=linux ;;
    *) die "unsupported system: $(uname -s). Flixor's server runs on macOS and Linux." ;;
  esac
  case "$(uname -m)" in
    arm64 | aarch64) arch=arm64 ;;
    x86_64 | amd64) arch=x64 ;;
    *) die "unsupported CPU: $(uname -m)" ;;
  esac
  if [ "$os" = darwin ] && [ "$arch" = x64 ] && [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = 1 ]; then
    arch=arm64 # Rosetta shell on Apple Silicon: install the native build.
  fi
  if [ "$os" = linux ] && [ -f /etc/alpine-release ]; then
    die "Alpine (musl) isn't supported yet; use the Docker image instead."
  fi
  target="$os-$arch"
  asset="flixor-server-$target.tar.gz"
}

# Sets download_url to this platform's archive in the requested or newest release that has one.
resolve_release() {
  if [ -n "${FLIXOR_RELEASE_BASE:-}" ]; then
    download_url="${FLIXOR_RELEASE_BASE%/}/$asset"
    return
  fi
  if [ -n "$version" ]; then
    download_url="https://github.com/$REPO/releases/download/$version/$asset"
    return
  fi
  releases=$(fetch_text "https://api.github.com/repos/$REPO/releases?per_page=50") \
    || die "couldn't reach GitHub to find the newest release"
  download_url=$(printf '%s\n' "$releases" \
    | grep -o "\"browser_download_url\": *\"[^\"]*/$asset\"" \
    | head -n 1 | sed 's/.*"\(https:[^"]*\)"/\1/')
  [ -n "$download_url" ] || die "no release has a server build for $target yet"
}

install_binary() {
  step "Downloading $(printf '%s' "$download_url" | sed 's|.*/download/||')"
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT INT TERM
  fetch "$download_url" "$tmp/$asset" || die "download failed: $download_url"
  fetch "$download_url.sha256" "$tmp/$asset.sha256" || die "checksum download failed: $download_url.sha256"
  expected=$(awk '{print $1}' "$tmp/$asset.sha256")
  actual=$(sha256 "$tmp/$asset")
  [ -n "$expected" ] && [ "$expected" = "$actual" ] || die "checksum mismatch for $asset; not installing it"
  say "Checksum verified."

  tar -xzf "$tmp/$asset" -C "$tmp" flixor-server
  mkdir -p "$bin_dir"
  # Replace by renaming: a running server keeps its old file until it restarts.
  mv -f "$tmp/flixor-server" "$bin_dir/flixor-server.new"
  chmod 755 "$bin_dir/flixor-server.new"
  mv -f "$bin_dir/flixor-server.new" "$bin_dir/flixor-server"
  say "Installed $("$bin_dir/flixor-server" --version) to $bin_dir"
}

# Sets KEY=value in the data folder's flixor.env, replacing an existing line.
set_env() { # key value
  env_file="$data_dir/flixor.env"
  mkdir -p "$data_dir"
  touch "$env_file"
  awk -v k="$1" -v v="$2" 'BEGIN { done = 0 }
    $0 ~ "^" k "=" { if (!done) print k "=" v; done = 1; next }
    { print }
    END { if (!done) print k "=" v }' "$env_file" > "$env_file.tmp"
  mv -f "$env_file.tmp" "$env_file"
}

get_env() { # key
  [ -f "$data_dir/flixor.env" ] || return 0
  sed -n "s/^$1=//p" "$data_dir/flixor.env" | tail -n 1
}

ensure_ffmpeg() {
  if ! have ffmpeg || ! have ffprobe; then
    if [ "$install_ffmpeg" = 0 ]; then
      warn "FFmpeg isn't installed. Direct play works; converting addon streams needs FFmpeg."
      return
    fi
    step "Installing FFmpeg (needed to convert addon streams the browser can't play)"
    if [ "$os" = darwin ]; then
      if have brew; then
        brew install ffmpeg || warn "brew install ffmpeg failed"
      else
        warn "Homebrew isn't installed. Install FFmpeg (https://brew.sh, then: brew install ffmpeg) and run this again."
      fi
    elif have apt-get; then
      if ! { as_root apt-get update -qq && as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ffmpeg; }; then
        warn "apt-get install ffmpeg failed"
      fi
    elif have dnf; then
      as_root dnf install -y ffmpeg || as_root dnf install -y ffmpeg-free || warn "dnf install ffmpeg failed"
    elif have pacman; then
      as_root pacman -S --noconfirm --needed ffmpeg || warn "pacman -S ffmpeg failed"
    elif have zypper; then
      as_root zypper --non-interactive install ffmpeg || warn "zypper install ffmpeg failed"
    else
      warn "No supported package manager found. Install FFmpeg yourself and run this again."
    fi
  fi
  if have ffmpeg && have ffprobe; then
    set_env FFMPEG_PATH "$(command -v ffmpeg)"
    set_env FFPROBE_PATH "$(command -v ffprobe)"
    say "FFmpeg: $(command -v ffmpeg)"
  fi
}

launchd_plist() { printf '%s/Library/LaunchAgents/%s.plist' "$HOME" "$LAUNCHD_LABEL"; }
systemd_unit() {
  if [ "$(id -u)" -eq 0 ]; then
    printf '/etc/systemd/system/%s.service' "$SERVICE_NAME"
  else
    printf '%s/systemd/user/%s.service' "${XDG_CONFIG_HOME:-$HOME/.config}" "$SERVICE_NAME"
  fi
}
systemctl_scope() { if [ "$(id -u)" -eq 0 ]; then systemctl "$@"; else systemctl --user "$@"; fi; }
has_systemd() { have systemctl && [ -d /run/systemd/system ]; }

install_service() {
  step "Setting up the background service"
  mkdir -p "$data_dir/logs"
  if [ "$os" = darwin ]; then
    plist=$(launchd_plist)
    mkdir -p "$(dirname "$plist")"
    cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LAUNCHD_LABEL</string>
  <key>ProgramArguments</key><array><string>$bin_dir/flixor-server</string></array>
  <key>EnvironmentVariables</key><dict><key>FLIXOR_HOME</key><string>$data_dir</string></dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardOutPath</key><string>$data_dir/logs/service.log</string>
  <key>StandardErrorPath</key><string>$data_dir/logs/service.log</string>
</dict>
</plist>
EOF
    domain="gui/$(id -u)"
    launchctl bootout "$domain/$LAUNCHD_LABEL" 2>/dev/null || true
    if ! launchctl bootstrap "$domain" "$plist" 2>/dev/null; then
      launchctl unload "$plist" 2>/dev/null || true
      launchctl load -w "$plist" || die "couldn't start the launchd service ($plist)"
    fi
    say "launchd agent $LAUNCHD_LABEL: starts at login, restarts if it stops."
    service_started=1
  elif has_systemd; then
    unit=$(systemd_unit)
    mkdir -p "$(dirname "$unit")"
    if [ "$(id -u)" -eq 0 ]; then wanted=multi-user.target; else wanted=default.target; fi
    cat > "$unit" <<EOF
[Unit]
Description=Flixor server
After=network-online.target
Wants=network-online.target

[Service]
Environment=FLIXOR_HOME=$data_dir
ExecStart=$bin_dir/flixor-server
Restart=on-failure
RestartSec=3

[Install]
WantedBy=$wanted
EOF
    systemctl_scope daemon-reload
    systemctl_scope enable "$SERVICE_NAME.service" >/dev/null 2>&1 || true
    systemctl_scope restart "$SERVICE_NAME.service" || die "couldn't start $SERVICE_NAME.service"
    if [ "$(id -u)" -ne 0 ]; then
      # A user service otherwise only runs while you are logged in.
      if ! loginctl enable-linger "$(id -un)" 2>/dev/null && ! as_root loginctl enable-linger "$(id -un)" 2>/dev/null; then
        warn "To start Flixor at boot without logging in, run: sudo loginctl enable-linger $(id -un)"
      fi
    fi
    say "systemd service $SERVICE_NAME ($unit): starts at boot, restarts if it fails."
    service_started=1
  else
    warn "No launchd or systemd found, so no service was set up. Start it with: $bin_dir/flixor-server"
  fi
}

remove_service() {
  if [ "$os" = darwin ]; then
    plist=$(launchd_plist)
    launchctl bootout "gui/$(id -u)/$LAUNCHD_LABEL" 2>/dev/null || launchctl unload "$plist" 2>/dev/null || true
    rm -f "$plist"
  elif has_systemd; then
    unit=$(systemd_unit)
    if [ -f "$unit" ]; then
      systemctl_scope disable --now "$SERVICE_NAME.service" 2>/dev/null || true
      rm -f "$unit"
      systemctl_scope daemon-reload || true
    fi
  fi
}

wait_until_up() {
  i=0
  while [ "$i" -lt 60 ]; do
    if fetch_text "http://127.0.0.1:$port/health" 2>/dev/null | grep -q healthy; then
      return 0
    fi
    i=$((i + 1))
    sleep 0.5
  done
  return 1
}

lan_address() {
  if [ "$os" = darwin ]; then
    for iface in en0 en1 en2; do
      addr=$(ipconfig getifaddr "$iface" 2>/dev/null || true)
      [ -n "$addr" ] && { printf '%s' "$addr"; return; }
    done
  else
    hostname -I 2>/dev/null | awk '{print $1}'
  fi
}

uninstall() {
  step "Removing the Flixor server"
  remove_service
  rm -f "$bin_dir/flixor-server"
  say "Removed $bin_dir/flixor-server and its service."
  if [ "$purge" = 1 ]; then
    rm -rf "$data_dir"
    say "Deleted $data_dir."
  else
    say "Your data is still in $data_dir (delete it, or run again with --uninstall --purge)."
  fi
}

main() {
  version=""
  port_flag=""
  bin_dir=""
  data_dir=""
  want_service=1
  install_ffmpeg=1
  do_uninstall=0
  purge=0
  service_started=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --version) [ $# -ge 2 ] || die "--version needs a tag"; version=$2; shift ;;
      --port) [ $# -ge 2 ] || die "--port needs a number"; port_flag=$2; shift ;;
      --bin-dir) [ $# -ge 2 ] || die "--bin-dir needs a folder"; bin_dir=$2; shift ;;
      --data-dir) [ $# -ge 2 ] || die "--data-dir needs a folder"; data_dir=$2; shift ;;
      --no-service) want_service=0 ;;
      --no-ffmpeg) install_ffmpeg=0 ;;
      --uninstall) do_uninstall=1 ;;
      --purge) purge=1 ;;
      -h | --help) usage; exit 0 ;;
      *) die "unknown option: $1 (see --help)" ;;
    esac
    shift
  done
  case "$port_flag" in
    "" | *[!0-9]*) [ -z "$port_flag" ] || die "--port must be a number" ;;
  esac

  if [ "$(id -u)" -eq 0 ]; then
    bin_dir=${bin_dir:-${FLIXOR_BIN_DIR:-/usr/local/bin}}
    data_dir=${data_dir:-${FLIXOR_HOME:-/var/lib/flixor}}
  else
    bin_dir=${bin_dir:-${FLIXOR_BIN_DIR:-$HOME/.local/bin}}
    data_dir=${data_dir:-${FLIXOR_HOME:-$HOME/.flixor}}
  fi

  detect_target

  if [ "$do_uninstall" = 1 ]; then
    uninstall
    exit 0
  fi

  say "Installing the Flixor server for $target"
  resolve_release
  install_binary

  mkdir -p "$data_dir"
  [ -z "$port_flag" ] || set_env PORT "$port_flag"
  port=$(get_env PORT)
  port=${port:-3001}

  ensure_ffmpeg

  if [ "$want_service" = 1 ]; then
    install_service
  fi

  step "Done"
  if [ "$service_started" = 1 ]; then
    if wait_until_up; then
      say "Flixor is running."
    else
      warn "The service didn't answer yet. Its log: $data_dir/logs/service.log"
    fi
  else
    say "Start it with: $bin_dir/flixor-server"
  fi
  say ""
  say "  Open:      http://localhost:$port"
  lan=$(lan_address || true)
  [ -z "$lan" ] || say "  Network:   http://$lan:$port"
  say "  Data:      $data_dir"
  say "  Settings:  $data_dir/flixor.env"
  say "  Update:    run this installer again"
  case ":$PATH:" in
    *":$bin_dir:"*) ;;
    *) say ""; say "Note: $bin_dir isn't on your PATH. Add it to run flixor-server by name." ;;
  esac
}

main "$@"
