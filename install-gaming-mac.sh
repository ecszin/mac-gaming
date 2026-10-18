#!/bin/bash
# =============================================================================
# install-gaming-mac.sh
# Steam + CrossOver + NotProton + Game Porting Toolkit — install and update
#
# First run (script downloaded to ~/Downloads):
#   chmod +x ~/Downloads/install-gaming-mac.sh
#   ~/Downloads/install-gaming-mac.sh
#   → creates ~/GPTK, installs a copy at ~/GPTK/MacGaming.sh and the "macgaming" shortcut
#
# After that, from any Terminal:
#   macgaming                         # opens the menu
#   macgaming 4                       # runs menu option 4 directly
#   (or: ~/GPTK/MacGaming.sh)
#
# GPTK downloads (option 3): 4.0 beta 3, 3.0 or 2.1. The download opens in the
# browser (requires Apple ID sign-in) and the script waits for the DMG in
# ~/Downloads; an already downloaded DMG is also accepted. Each version is kept
# in its own folder, so option 3 also switches between installed builds.
#
# Layout maintained:
#   ~/GPTK/MacGaming.sh     → this script (installed automatically)
#   ~/GPTK/<version>/       → external/ and wine/ (DMG's redist/lib folder), one folder per version
#   ~/GPTK/current          → link to the version in use (switching versions = changing the link)
#   ~/GPTK/backup-<date>/   → backup of each target before it is overwritten
#
# GPTK targets:
#   NotProton (Steam games): ~/Library/Application Support/notproton/runners/crossover-*/CrossOver/lib64/apple_gptk
#   CrossOver.app:           /Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib64/apple_gptk
#   Game prefixes:           ~/Library/Application Support/Steam/steamapps/compatdata/<APPID>/pfx/drive_c/windows/system32
# =============================================================================

# Ensure bash even when invoked as "zsh install-gaming-mac.sh"
[ -z "${BASH_VERSION:-}" ] && exec /bin/bash "$0" "$@"
set -uo pipefail
shopt -s nullglob

# ---------- messages ---------------------------------------------------------
info()  { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()    { printf '\033[32m ✔ \033[0m %s\n' "$*"; }
warn()  { printf '\033[33m ! \033[0m %s\n' "$*"; }
error() { printf '\033[31m ✖ \033[0m %s\n' "$*" >&2; }
ask() { printf '\033[1m%s\033[0m ' "$1" >&2; read -r; printf '%s' "$REPLY"; }
confirm() { [[ "$(ask "$1 [y/N]")" =~ ^[yY]$ ]]; }
# exists <paths/globs...> — true if at least one exists (safe with nullglob)
exists() { for x in "$@"; do [ -e "$x" ] && return 0; done; return 1; }
backup_dir() { printf '%s' ~/GPTK/backup-"$(date +%Y%m%d-%H%M)"; }

trap 'hdiutil detach /tmp/gptk-dmg -quiet 2>/dev/null' EXIT

# ---------- checks -----------------------------------------------------------
check_mac() {
  [ "$(uname -s)" = "Darwin" ] || { error "macOS only."; exit 1; }
  [ "$(uname -m)" = "arm64" ]  || { error "Requires Apple Silicon."; exit 1; }
}

steam_closed() {
  if pgrep -xq steam_osx || pgrep -iq wine; then
    error "Quit Steam and any running games before continuing."
    return 1
  fi
}

has_build() {
  [ -d ~/GPTK/current/external ] && [ -d ~/GPTK/current/wine ] && return 0
  error "No GPTK build in ~/GPTK/current. Run option 3 first."
  return 1
}

# Backward compatibility with older layouts:
#  - renames the old ~/GPTK/atual link to ~/GPTK/current
#  - creates ~/GPTK/current pointing to the newest build if no link exists
migrate_layout() {
  if [ -L ~/GPTK/atual ] && [ ! -e ~/GPTK/current ]; then
    mv -n ~/GPTK/atual ~/GPTK/current && ok "~/GPTK/atual renamed to ~/GPTK/current"
  fi
  [ -e ~/GPTK/current ] && return
  exists ~/GPTK/[0-9]*/ || return
  ln -sfn "$(basename "$(ls -td ~/GPTK/[0-9]*/ | head -n1)")" ~/GPTK/current
  ok "~/GPTK/current → $(readlink ~/GPTK/current)"
}

# ---------- 1. prerequisites -------------------------------------------------
install_rosetta() {
  if /usr/bin/arch -x86_64 /usr/bin/true &>/dev/null; then
    ok "Rosetta 2 installed"
    return
  fi
  warn "Rosetta 2 not found — installing (may ask for your password)"
  sudo /usr/sbin/softwareupdate --install-rosetta --agree-to-license || { error "Failed to install Rosetta 2."; return 1; }
  /usr/bin/arch -x86_64 /usr/bin/true &>/dev/null || { error "x86_64 test failed. Restart the Mac and try again."; return 1; }
  ok "Rosetta 2 installed"
}

load_brew() {
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$b" ] || continue
    eval "$("$b" shellenv)"
    grep -qsF "eval \"\$($b shellenv)\"" ~/.zprofile \
      || printf '\neval "$(%s shellenv)"\n' "$b" >> ~/.zprofile
    return 0
  done
  return 1
}

install_brew() {
  command -v brew &>/dev/null || load_brew
  if ! command -v brew &>/dev/null; then
    warn "Homebrew not found — installing (will ask for an administrator password)"
    sudo -v || { error "No administrator privileges."; return 1; }
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
      || { error "Homebrew installation failed."; return 1; }
    load_brew || { error "Homebrew installed, but not found in /opt/homebrew."; return 1; }
  fi
  [[ "$(command -v brew)" == /opt/homebrew/* ]] || warn "brew found at $(command -v brew) (not the native arm64 one)."
  ok "Homebrew $(brew --version | head -n1 | awk '{print $2}')"
  info "brew update"
  brew update --quiet
}

prerequisites() {
  info "Prerequisites"
  ok "macOS $(sw_vers -productVersion)"
  [ "$(sw_vers -productVersion | cut -d. -f1)" -ge 27 ] || warn "GPTK 4 was built for macOS 27."
  [ "$(( $(sysctl -n hw.memsize) / 1073741824 ))" -ge 16 ] || warn "Less than 16 GB of RAM."
  install_rosetta && install_brew
}

# ---------- 2. apps ----------------------------------------------------------
install_cask() {
  if ! brew list --cask "${1##*/}" &>/dev/null; then
    info "Installing $1"
    brew install --cask "$1" || { error "Failed: $1"; return 1; }
    ok "${1##*/} installed"
  elif [ -n "$(brew outdated --cask --quiet "$1" 2>/dev/null)" ]; then
    info "Updating ${1##*/}"
    brew upgrade --cask "$1" || { error "Failed to update ${1##*/}"; return 1; }
    ok "${1##*/} updated"
  else
    ok "${1##*/} is already up to date"
  fi
}

install_apps() {
  command -v brew &>/dev/null || prerequisites || return 1
  install_cask steam
  install_cask crossover
  install_cask notprotonnot/notproton/notproton
  warn "Next: open NotProton → patch Steam → deploy CrossOver as a Compatibility Tool."
}

# ---------- 3. GPTK build ----------------------------------------------------
# Available Apple downloads: "<version name>|<URL>" (newest first)
GPTK_DOWNLOADS=(
  "4.0b3|https://download.developer.apple.com/Developer_Tools/Evaluation_environment_for_Windows_games_4.0_beta_1/Evaluation_environment_for_Windows_games_4.0_beta_3.dmg"
  "3.0|https://download.developer.apple.com/Developer_Tools/Evaluation_environment_for_Windows_games_3.0/Evaluation_environment_for_Windows_games_3.0.dmg"
  "2.1|https://download.developer.apple.com/Developer_Tools/Game_Porting_Toolkit_1.1/Evaluation_environment_for_Windows_games_2.1.dmg"
)

latest_dmg() {
  exists ~/Downloads/*[Pp]orting*[Tt]oolkit*.dmg ~/Downloads/*[Ee]valuation*[Ww]indows*.dmg || return 0
  ls -t ~/Downloads/*[Pp]orting*[Tt]oolkit*.dmg ~/Downloads/*[Ee]valuation*[Ww]indows*.dmg 2>/dev/null | head -n1
}

# install_build <dmg> <version>
install_build() {
  [ -f "$1" ] || { error "DMG not found: ${1:-(empty)}"; return 1; }
  [ -n "$2" ] || { error "Please provide a version name."; return 1; }

  info "Mounting $1"
  hdiutil detach /tmp/gptk-dmg -quiet 2>/dev/null
  hdiutil attach "$1" -nobrowse -readonly -mountpoint /tmp/gptk-dmg -quiet || { error "Failed to mount the DMG."; return 1; }

  if [ ! -d /tmp/gptk-dmg/redist/lib/external ] || [ ! -d /tmp/gptk-dmg/redist/lib/wine ]; then
    error "redist/lib/{external,wine} not found in the DMG:"
    ls /tmp/gptk-dmg >&2
    hdiutil detach /tmp/gptk-dmg -quiet
    return 1
  fi

  info "Copying to ~/GPTK/$2"
  mkdir -p ~/GPTK/"$2"
  ditto /tmp/gptk-dmg/redist/lib/ ~/GPTK/"$2"/
  hdiutil detach /tmp/gptk-dmg -quiet
  xattr -dr com.apple.quarantine ~/GPTK/"$2" 2>/dev/null
  ln -sfn "$2" ~/GPTK/current
  ok "Build $2 installed — ~/GPTK/current → $2"
}

# download_gptk <URL> — Apple requires Apple ID sign-in (browser cookie), so the link
# is opened in the default browser and the script waits for the file in ~/Downloads.
# Sets DOWNLOADED_DMG to the downloaded file's path.
download_gptk() {
  DOWNLOADED_DMG=~/Downloads/"$(basename "$1")"
  if [ -f "$DOWNLOADED_DMG" ] && ! exists "$DOWNLOADED_DMG.download" ~/Downloads/*.crdownload; then
    ok "$(basename "$1") is already in ~/Downloads"
    return 0
  fi
  info "Opening the download in your browser — sign in with your Apple ID if prompted"
  open "$1"
  info "Waiting for ~/Downloads/$(basename "$1")  (Ctrl+C to cancel)"
  until [ -f "$DOWNLOADED_DMG" ] \
        && ! exists "$DOWNLOADED_DMG.download" ~/Downloads/*.crdownload; do
    printf '.'
    sleep 3
  done
  echo
  ok "Download complete"
}

# Accepts a typed path or a file dragged into Terminal (strips "\ " and quotes)
choose_dmg() {
  ask "DMG path (you can drag the file here) [Enter = $(latest_dmg)]:" >/dev/null
  printf '%s' "${REPLY:-$(latest_dmg)}" | sed -e 's/\\ / /g' -e "s/^[\"']//" -e "s/[\"']\$//" -e 's/ *$//'
}

# Derives the version from the DMG name: ..._4.0_beta_3.dmg → 4.0b3
dmg_version() {
  basename "$1" | sed -n 's/.*_\([0-9][0-9.]*\)_beta_\([0-9][0-9]*\)\.dmg$/\1b\2/p; s/.*_\([0-9][0-9.]*\)\.dmg$/\1/p' | head -n1
}

# install_dmg <dmg> — asks for the version (Enter = derived from the name) and installs
install_dmg() {
  ask "Version name [Enter = $(dmg_version "$1")]:" >/dev/null
  install_build "$1" "${REPLY:-$(dmg_version "$1")}"
}

build_menu() {
  local i=1 e v url c status
  info "GPTK build (in use: $(readlink ~/GPTK/current 2>/dev/null || echo none))"
  for e in "${GPTK_DOWNLOADS[@]}"; do
    v="${e%%|*}"; url="${e#*|}"; status=""
    [ -f ~/Downloads/"$(basename "$url")" ] && status="  [DMG in ~/Downloads]"
    [ -d ~/GPTK/"$v"/external ] && status="  [installed]"
    printf '  %d) GPTK %s%s\n' "$i" "$v" "$status"
    i=$((i + 1))
  done
  printf '  %d) Use a DMG I already have\n' "$i"
  c="$(ask "Choice [1]:")"; c="${c:-1}"

  if [ "$c" = "$i" ]; then
    install_dmg "$(choose_dmg)"
    return
  fi
  if ! [[ "$c" =~ ^[0-9]+$ ]] || [ "$c" -lt 1 ] || [ "$c" -gt "${#GPTK_DOWNLOADS[@]}" ]; then
    error "Invalid choice: $c"
    return 1
  fi

  e="${GPTK_DOWNLOADS[$((c - 1))]}"; v="${e%%|*}"; url="${e#*|}"

  # Already installed → just switch the link (no download needed)
  if [ -d ~/GPTK/"$v"/external ] && [ -d ~/GPTK/"$v"/wine ] \
     && confirm "Build $v is already installed. Just switch ~/GPTK/current to it? (N = reinstall)"; then
    ln -sfn "$v" ~/GPTK/current
    ok "~/GPTK/current → $v  (use option 7 to apply it)"
    return
  fi

  download_gptk "$url" || return 1
  install_build "$DOWNLOADED_DMG" "$v" && info "Use option 7 to apply build $v."
}

# ---------- 4–6. apply -------------------------------------------------------
# apply_gptk <apple_gptk target> <backup label>
apply_gptk() {
  [ -d "$1" ] || { warn "Not found: $1"; return 1; }
  mkdir -p "$(backup_dir)/$2"
  ditto "$1" "$(backup_dir)/$2/apple_gptk"
  printf '%s\n' "$1" > "$(backup_dir)/$2/target"
  ditto ~/GPTK/current/external "$1/external"
  ditto ~/GPTK/current/wine "$1/wine"
  xattr -dr com.apple.quarantine "$1" 2>/dev/null
  ok "GPTK $(readlink ~/GPTK/current) → $2"
}

apply_notproton() {
  has_build && steam_closed || return 1
  exists ~/"Library/Application Support/notproton/runners"/crossover-*/ \
    || { warn "No NotProton runner found. Deploy CrossOver in NotProton first."; return 1; }
  for r in ~/"Library/Application Support/notproton/runners"/crossover-*/; do
    apply_gptk "${r%/}/CrossOver/lib64/apple_gptk" "notproton-$(basename "$r")"
  done
}

# Locates the apple_gptk folder inside CrossOver.app (layout changes between versions/Preview)
crossover_apple_gptk() {
  find /Applications/CrossOver.app/Contents -type d -name apple_gptk -prune 2>/dev/null | head -n1
}

apply_crossover() {
  has_build && steam_closed || return 1
  [ -d /Applications/CrossOver.app ] || { warn "CrossOver.app is not in /Applications."; return 1; }
  if [ -z "$(crossover_apple_gptk)" ]; then
    warn "This CrossOver.app version has no apple_gptk folder — nothing to apply here."
    warn "Steam games use the NotProton runner (option 4), which already gets the GPTK."
    find /Applications/CrossOver.app/Contents -type d -name D3DMetal.framework -prune 2>/dev/null \
      | sed 's/^/     D3DMetal found at: /'
    return 1
  fi
  apply_gptk "$(crossover_apple_gptk)" crossover-app \
    || warn "\"Operation not permitted\"? System Settings > Privacy & Security > App Management → allow Terminal."
}

# apply_pfx [APPID]  (no APPID = all existing prefixes)
apply_pfx() {
  has_build && steam_closed || return 1
  exists ~/"Library/Application Support/Steam/steamapps/compatdata"/${1:-*}/pfx/drive_c/windows/system32/ \
    || { warn "No prefix found${1:+ for APPID $1} (has the game been launched at least once?)"; return 1; }
  for p in ~/"Library/Application Support/Steam/steamapps/compatdata"/${1:-*}/pfx/drive_c/windows/system32/; do
    [ -d "$p" ] || continue
    backup_pfx "$p" "$(backup_dir)/pfx-$(basename "${p%/pfx/drive_c/windows/system32/}")"
    cp -f ~/GPTK/current/wine/x86_64-windows/*.dll "$p"
    ok "Prefix $(basename "${p%/pfx/drive_c/windows/system32/}") updated"
  done
}

# backup_pfx <system32> <backup dir> — saves only the DLLs the GPTK will overwrite
backup_pfx() {
  mkdir -p "$2"
  printf '%s\n' "$1" > "$2/target"
  for d in ~/GPTK/current/wine/x86_64-windows/*.dll; do
    [ -f "$1$(basename "$d")" ] && cp -p "$1$(basename "$d")" "$2/"
  done
}

apply_all() {
  apply_notproton
  apply_pfx
  apply_crossover
}

# ---------- 8. verify --------------------------------------------------------
verify() {
  info "Build in use"
  if [ -e ~/GPTK/current ]; then ok "~/GPTK/current → $(readlink ~/GPTK/current)"; else warn "None"; fi
  info "Available builds"
  if exists ~/GPTK/[0-9]*/; then
    for v in ~/GPTK/[0-9]*/; do printf '  %s\n' "$(basename "$v")"; done
  else
    warn "None"
  fi
  info "D3DMetal on disk"
  find /Applications ~/Library -name D3DMetal.framework -type d 2>/dev/null | while read -r; do
    printf '  %-12s %s\n' "$(defaults read "$REPLY/Versions/A/Resources/Info.plist" CFBundleShortVersionString 2>/dev/null)" "$REPLY"
  done
  info "D3DMetal in use (requires a running game)"
  pgrep -if wine | xargs -I{} lsof -p {} 2>/dev/null | grep -i D3DMetal | awk '{print $NF}' | sort -u | grep . \
    || warn "No game running"
  info "HUD: Steam launch option →  MTL_HUD_ENABLED=1 %command%"
}

# ---------- 9. restore -------------------------------------------------------
restore() {
  steam_closed || return 1
  exists ~/GPTK/backup-*/ || { warn "No backups in ~/GPTK."; return 1; }
  info "Backups (most recent last):"
  PS3="Which one to restore? "
  select b in $(ls -1d ~/GPTK/backup-*/ | tail -n 8); do
    [ -n "$b" ] && break
  done
  [ -n "${b:-}" ] || return 1
  ls -1 "$b"
  confirm "Restore these targets?" || return
  for t in "$b"*/; do
    # "destino" = target file written by older (Portuguese) versions of this script
    dest_file="${t}target"; [ -f "$dest_file" ] || dest_file="${t}destino"
    if [ -d "${t}apple_gptk" ]; then
      ditto "${t}apple_gptk" "$(cat "$dest_file")"
    else
      find "$t" -name '*.dll' -exec cp -f {} "$(cat "$dest_file")" \;
    fi
    ok "Restored: $(basename "$t")"
  done
}

# ---------- 1. full install --------------------------------------------------
full_install() {
  prerequisites || return 1
  install_apps || return 1
  [ -e ~/GPTK/current ] || build_menu || return 1
  confirm "Apply the GPTK now?" && apply_all
}

# ---------- 10. uninstall ----------------------------------------------------
uninstall() {
  steam_closed || return 1
  warn "This removes Steam, CrossOver, NotProton, ~/GPTK (builds, backups, this script) and the macgaming shortcut."
  [ "$(ask "Type UNINSTALL to confirm:")" = "UNINSTALL" ] || { info "Cancelled."; return 1; }

  command -v brew &>/dev/null || load_brew

  if command -v brew &>/dev/null; then
    if confirm "Also delete app data (installed games, local saves, CrossOver bottles, NotProton runners)?"; then
      for c in notprotonnot/notproton/notproton crossover steam; do
        brew list --cask "${c##*/}" &>/dev/null && brew uninstall --cask --zap "$c" && ok "${c##*/} removed (with data)"
      done
    else
      for c in notprotonnot/notproton/notproton crossover steam; do
        brew list --cask "${c##*/}" &>/dev/null && brew uninstall --cask "$c" && ok "${c##*/} removed (data kept)"
      done
    fi
    brew untap notprotonnot/notproton &>/dev/null && ok "Tap notprotonnot/notproton removed"
  else
    warn "brew not found — removing the apps directly from /Applications"
    rm -rf /Applications/Steam.app /Applications/CrossOver.app /Applications/NotProton.app
  fi

  rm -rf ~/"Library/Application Support/notproton"
  ok "NotProton runners removed"

  sed -i '' -e '/^# MacGaming (GPTK/d' -e '/^alias macgaming=/d' ~/.zshrc 2>/dev/null
  ok "macgaming shortcut removed from ~/.zshrc"

  if confirm "Also uninstall Homebrew? (removes ALL packages installed with it)"; then
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)" \
      && sed -i '' '/brew shellenv/d' ~/.zprofile 2>/dev/null && ok "Homebrew removed"
  fi

  rm -rf ~/GPTK
  ok "~/GPTK removed"
  info "Uninstall complete. Rosetta 2 is a system component and was kept."
  exit 0
}

# ---------- self-install -----------------------------------------------------
# Copies this script to ~/GPTK/MacGaming.sh (updates it if the downloaded version differs),
# clears quarantine/sets exec permission and creates the "macgaming" zsh shortcut.
install_script() {
  if ! cmp -s "$0" ~/GPTK/MacGaming.sh; then
    cp -f "$0" ~/GPTK/MacGaming.sh
    ok "Script copied to ~/GPTK/MacGaming.sh"
  fi
  chmod 755 ~/GPTK/MacGaming.sh
  xattr -d com.apple.quarantine ~/GPTK/MacGaming.sh 2>/dev/null
  grep -qsF "alias macgaming=" ~/.zshrc \
    || printf "\n# MacGaming (GPTK · CrossOver · NotProton · Steam)\nalias macgaming='~/GPTK/MacGaming.sh'\n" >> ~/.zshrc

  # Run from outside ~/GPTK (e.g. ~/Downloads) → tell the user where to run it from now on
  if [ "$(cd "$(dirname "$0")" && pwd -P)/$(basename "$0")" != "$(cd ~/GPTK && pwd -P)/MacGaming.sh" ]; then
    printf '\n\033[1;33m'
    cat <<'EOF'
 ┌───────────────────────────────────────────────────────────────┐
 │  The script has been copied to  ~/GPTK/MacGaming.sh           │
 │                                                               │
 │  From now on, run it from this path:                          │
 │      ~/GPTK/MacGaming.sh                                      │
 │  or, in a new Terminal window, with the shortcut:             │
 │      macgaming                                                │
 │                                                               │
 │  The file downloaded to ~/Downloads can be deleted.           │
 └───────────────────────────────────────────────────────────────┘
EOF
    printf '\033[0m\n'
    [ -t 0 ] && [ -z "${1:-}" ] && ask "Press Enter to continue…" >/dev/null
  fi
}

# ---------- menu -------------------------------------------------------------
show_menu() {
  clear
  cat <<EOF
 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  GPTK · CrossOver · NotProton · Steam
  Build in use: $(readlink ~/GPTK/current 2>/dev/null || echo "none")
 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  1) Full install
  2) Install/update apps (Steam, CrossOver, NotProton)
  3) Download/install/switch GPTK build (4.0b3, 3.0, 2.1 or local DMG)
  4) Apply GPTK to NotProton (Steam games)
  5) Apply GPTK to game prefixes
  6) Apply GPTK to CrossOver.app
  7) Apply to everything (4 + 5 + 6)
  8) Check versions
  9) Restore backup
 10) Uninstall everything
  0) Exit
 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  WHEN TO UPDATE  (quit Steam and games first)
  • New/other GPTK version    → 3, then 7
  • NotProton fetched a runner → 4
  • New game installed        → launch it once, quit, then use 5
  • CrossOver updated         → 6
  • Apps (Steam/CrossOver/NotProton) → 2, then 7
  • Check: 8  ·  Steam HUD: MTL_HUD_ENABLED=1 %command%
  • First launch after a GPTK change is slow (Rosetta translating)
 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
}

run_option() {
  case "$1" in
    1) full_install ;;
    2) install_apps ;;
    3) build_menu ;;
    4) apply_notproton ;;
    5) apply_pfx "$(ask "APPID [Enter = all]:")" ;;
    6) apply_crossover ;;
    7) apply_all ;;
    8) verify ;;
    9) restore ;;
    10) uninstall ;;
    0) exit 0 ;;
    *) error "Invalid option: $1" ;;
  esac
}

check_mac
mkdir -p ~/GPTK
install_script "${1:-}"
migrate_layout

if [ -n "${1:-}" ]; then
  run_option "$1"
  exit
fi

while true; do
  show_menu
  run_option "$(ask "Option:")"
  ask $'\nPress Enter to return to the menu…' >/dev/null
done
