#!/bin/bash
# =============================================================================
# install-gaming-mac.sh
# Steam + CrossOver + NotProton + Game Porting Toolkit — instalação e atualização
#
# Primeira execução (script baixado em ~/Downloads):
#   chmod +x ~/Downloads/install-gaming-mac.sh
#   ~/Downloads/install-gaming-mac.sh
#   → cria ~/GPTK, instala uma cópia em ~/GPTK/MacGaming.sh e o atalho "macgaming"
#
# Depois disso, em qualquer Terminal:
#   macgaming                         # abre o menu
#   macgaming 4                       # executa direto a opção 4 do menu
#   (ou: ~/GPTK/MacGaming.sh)
#
# GPTK 4.0 beta 3: a opção 3 abre o download da Apple no navegador (exige login
# com Apple ID) e aguarda o DMG em ~/Downloads; também aceita um DMG já baixado.
#
# Estrutura mantida:
#   ~/GPTK/MacGaming.sh     → este script (instalado automaticamente)
#   ~/GPTK/<versão>/        → external/ e wine/ (pasta redist/lib do DMG), uma pasta por versão
#   ~/GPTK/atual            → link para a versão em uso (troca de versão = trocar o link)
#   ~/GPTK/backup-<data>/   → backup de cada destino antes de sobrescrever
#
# Destinos do GPTK:
#   NotProton (jogos Steam): ~/Library/Application Support/notproton/runners/crossover-*/CrossOver/lib64/apple_gptk
#   CrossOver.app:           /Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib64/apple_gptk
#   Prefixos dos jogos:      ~/Library/Application Support/Steam/steamapps/compatdata/<APPID>/pfx/drive_c/windows/system32
# =============================================================================

# Garante bash mesmo se chamado com "zsh install-gaming-mac.sh"
[ -z "${BASH_VERSION:-}" ] && exec /bin/bash "$0" "$@"
set -uo pipefail
shopt -s nullglob

# ---------- mensagens --------------------------------------------------------
info()  { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()    { printf '\033[32m ✔ \033[0m %s\n' "$*"; }
aviso() { printf '\033[33m ! \033[0m %s\n' "$*"; }
erro()  { printf '\033[31m ✖ \033[0m %s\n' "$*" >&2; }
pergunta() { printf '\033[1m%s\033[0m ' "$1" >&2; read -r; printf '%s' "$REPLY"; }
confirma() { [[ "$(pergunta "$1 [s/N]")" =~ ^[sS]$ ]]; }
# existe <caminhos/glob...> — verdadeiro se pelo menos um existir (seguro com nullglob)
existe() { for x in "$@"; do [ -e "$x" ] && return 0; done; return 1; }
pasta_backup() { printf '%s' ~/GPTK/backup-"$(date +%Y%m%d-%H%M)"; }

trap 'hdiutil detach /tmp/gptk-dmg -quiet 2>/dev/null' EXIT

# ---------- checagens --------------------------------------------------------
checa_mac() {
  [ "$(uname -s)" = "Darwin" ] || { erro "Somente macOS."; exit 1; }
  [ "$(uname -m)" = "arm64" ]  || { erro "Requer Apple Silicon."; exit 1; }
}

steam_fechado() {
  if pgrep -xq steam_osx || pgrep -iq wine; then
    erro "Feche o Steam e os jogos antes de continuar."
    return 1
  fi
}

tem_build() {
  [ -d ~/GPTK/atual/external ] && [ -d ~/GPTK/atual/wine ] && return 0
  erro "Nenhuma build do GPTK em ~/GPTK/atual. Use a opção 3 primeiro."
  return 1
}

# Compatibilidade com o layout antigo: cria ~/GPTK/atual apontando para a build mais recente
migra_layout() {
  [ -e ~/GPTK/atual ] && return
  existe ~/GPTK/[0-9]*/ || return
  ln -sfn "$(basename "$(ls -td ~/GPTK/[0-9]*/ | head -n1)")" ~/GPTK/atual
  ok "~/GPTK/atual → $(readlink ~/GPTK/atual)"
}

# ---------- 1. pré-requisitos ------------------------------------------------
instala_rosetta() {
  if /usr/bin/arch -x86_64 /usr/bin/true &>/dev/null; then
    ok "Rosetta 2 instalado"
    return
  fi
  aviso "Rosetta 2 não encontrado — instalando (pode pedir senha)"
  sudo /usr/sbin/softwareupdate --install-rosetta --agree-to-license || { erro "Falha ao instalar o Rosetta 2."; return 1; }
  /usr/bin/arch -x86_64 /usr/bin/true &>/dev/null || { erro "Teste x86_64 falhou. Reinicie o Mac e tente de novo."; return 1; }
  ok "Rosetta 2 instalado"
}

carrega_brew() {
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$b" ] || continue
    eval "$("$b" shellenv)"
    grep -qsF "eval \"\$($b shellenv)\"" ~/.zprofile \
      || printf '\neval "$(%s shellenv)"\n' "$b" >> ~/.zprofile
    return 0
  done
  return 1
}

instala_brew() {
  command -v brew &>/dev/null || carrega_brew
  if ! command -v brew &>/dev/null; then
    aviso "Homebrew não encontrado — instalando (vai pedir senha de administrador)"
    sudo -v || { erro "Sem permissão de administrador."; return 1; }
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
      || { erro "Falha na instalação do Homebrew."; return 1; }
    carrega_brew || { erro "Homebrew instalado, mas não encontrado em /opt/homebrew."; return 1; }
  fi
  [[ "$(command -v brew)" == /opt/homebrew/* ]] || aviso "brew em $(command -v brew) (não é o arm64 nativo)."
  ok "Homebrew $(brew --version | head -n1 | awk '{print $2}')"
  info "brew update"
  brew update --quiet
}

prerequisitos() {
  info "Pré-requisitos"
  ok "macOS $(sw_vers -productVersion)"
  [ "$(sw_vers -productVersion | cut -d. -f1)" -ge 27 ] || aviso "GPTK 4 foi feito para o macOS 27."
  [ "$(( $(sysctl -n hw.memsize) / 1073741824 ))" -ge 16 ] || aviso "Menos de 16 GB de RAM."
  instala_rosetta && instala_brew
}

# ---------- 2. apps ----------------------------------------------------------
instala_cask() {
  if ! brew list --cask "${1##*/}" &>/dev/null; then
    info "Instalando $1"
    brew install --cask "$1" || { erro "Falha: $1"; return 1; }
    ok "${1##*/} instalado"
  elif [ -n "$(brew outdated --cask --quiet "$1" 2>/dev/null)" ]; then
    info "Atualizando ${1##*/}"
    brew upgrade --cask "$1" || { erro "Falha ao atualizar ${1##*/}"; return 1; }
    ok "${1##*/} atualizado"
  else
    ok "${1##*/} já está na última versão"
  fi
}

instala_apps() {
  command -v brew &>/dev/null || prerequisitos || return 1
  instala_cask steam
  instala_cask crossover
  instala_cask notprotonnot/notproton/notproton
  aviso "Depois: abra o NotProton → patch no Steam → deploy do CrossOver como Compatibility Tool."
}

# ---------- 3. build do GPTK -------------------------------------------------
dmg_recente() {
  existe ~/Downloads/*[Pp]orting*[Tt]oolkit*.dmg ~/Downloads/*[Ee]valuation*[Ww]indows*.dmg || return 0
  ls -t ~/Downloads/*[Pp]orting*[Tt]oolkit*.dmg ~/Downloads/*[Ee]valuation*[Ww]indows*.dmg 2>/dev/null | head -n1
}

# instala_build <dmg> <versão>
instala_build() {
  [ -f "$1" ] || { erro "DMG não encontrado: ${1:-(vazio)}"; return 1; }
  [ -n "$2" ] || { erro "Informe o nome da versão."; return 1; }

  info "Montando $1"
  hdiutil detach /tmp/gptk-dmg -quiet 2>/dev/null
  hdiutil attach "$1" -nobrowse -readonly -mountpoint /tmp/gptk-dmg -quiet || { erro "Falha ao montar o DMG."; return 1; }

  if [ ! -d /tmp/gptk-dmg/redist/lib/external ] || [ ! -d /tmp/gptk-dmg/redist/lib/wine ]; then
    erro "redist/lib/{external,wine} não encontrado no DMG:"
    ls /tmp/gptk-dmg >&2
    hdiutil detach /tmp/gptk-dmg -quiet
    return 1
  fi

  info "Copiando para ~/GPTK/$2"
  mkdir -p ~/GPTK/"$2"
  ditto /tmp/gptk-dmg/redist/lib/ ~/GPTK/"$2"/
  hdiutil detach /tmp/gptk-dmg -quiet
  xattr -dr com.apple.quarantine ~/GPTK/"$2" 2>/dev/null
  ln -sfn "$2" ~/GPTK/atual
  ok "Build $2 instalada — ~/GPTK/atual → $2"
}

# Download do GPTK 4.0 beta 3 — a Apple exige login com Apple ID (cookie do navegador),
# então o link é aberto no navegador padrão e o script aguarda o arquivo em ~/Downloads.
baixa_gptk() {
  if [ -f ~/Downloads/Evaluation_environment_for_Windows_games_4.0_beta_3.dmg ]; then
    ok "DMG do GPTK 4.0 beta 3 já está em ~/Downloads"
    return 0
  fi
  info "Abrindo o download no navegador — faça login com seu Apple ID se for pedido"
  open "https://download.developer.apple.com/Developer_Tools/Evaluation_environment_for_Windows_games_4.0_beta_1/Evaluation_environment_for_Windows_games_4.0_beta_3.dmg"
  info "Aguardando ~/Downloads/Evaluation_environment_for_Windows_games_4.0_beta_3.dmg  (Ctrl+C cancela)"
  until [ -f ~/Downloads/Evaluation_environment_for_Windows_games_4.0_beta_3.dmg ] \
        && ! existe ~/Downloads/Evaluation_environment_for_Windows_games_4.0_beta_3.dmg.download \
                    ~/Downloads/*.crdownload; do
    printf '.'
    sleep 3
  done
  echo
  ok "Download concluído"
}

# Aceita caminho digitado ou arrastado para o Terminal (remove "\ " e aspas)
escolhe_dmg() {
  pergunta "Caminho do DMG (pode arrastar o arquivo) [Enter = $(dmg_recente)]:" >/dev/null
  printf '%s' "${REPLY:-$(dmg_recente)}" | sed -e 's/\\ / /g' -e "s/^[\"']//" -e "s/[\"']\$//" -e 's/ *$//'
}

# Deduz a versão pelo nome do DMG: ..._4.0_beta_3.dmg → 4.0b3
versao_do_dmg() {
  basename "$1" | sed -n 's/.*_\([0-9][0-9.]*\)_beta_\([0-9][0-9]*\)\.dmg$/\1b\2/p; s/.*_\([0-9][0-9.]*\)\.dmg$/\1/p' | head -n1
}

# instala_dmg <dmg> — pergunta a versão (Enter = deduzida do nome) e instala
instala_dmg() {
  pergunta "Nome da versão [Enter = $(versao_do_dmg "$1")]:" >/dev/null
  instala_build "$1" "${REPLY:-$(versao_do_dmg "$1")}"
}

menu_build() {
  if [ -f ~/Downloads/Evaluation_environment_for_Windows_games_4.0_beta_3.dmg ] \
     || confirma "Baixar o GPTK 4.0 beta 3 da Apple agora? (N = usar um DMG que você já tem)"; then
    baixa_gptk || return 1
  fi
  instala_dmg "$(escolhe_dmg)"
}

# ---------- 4–6. aplicar -----------------------------------------------------
# aplica_gptk <destino apple_gptk> <rótulo do backup>
aplica_gptk() {
  [ -d "$1" ] || { aviso "Não encontrado: $1"; return 1; }
  mkdir -p "$(pasta_backup)/$2"
  ditto "$1" "$(pasta_backup)/$2/apple_gptk"
  printf '%s\n' "$1" > "$(pasta_backup)/$2/destino"
  ditto ~/GPTK/atual/external "$1/external"
  ditto ~/GPTK/atual/wine "$1/wine"
  xattr -dr com.apple.quarantine "$1" 2>/dev/null
  ok "GPTK $(readlink ~/GPTK/atual) → $2"
}

aplica_notproton() {
  tem_build && steam_fechado || return 1
  existe ~/"Library/Application Support/notproton/runners"/crossover-*/ \
    || { aviso "Nenhum runner do NotProton. Faça o deploy do CrossOver no NotProton primeiro."; return 1; }
  for r in ~/"Library/Application Support/notproton/runners"/crossover-*/; do
    aplica_gptk "${r%/}/CrossOver/lib64/apple_gptk" "notproton-$(basename "$r")"
  done
}

# Localiza a pasta apple_gptk dentro do CrossOver.app (o layout muda entre versões/Preview)
apple_gptk_crossover() {
  find /Applications/CrossOver.app/Contents -type d -name apple_gptk -prune 2>/dev/null | head -n1
}

aplica_crossover() {
  tem_build && steam_fechado || return 1
  [ -d /Applications/CrossOver.app ] || { aviso "CrossOver.app não está em /Applications."; return 1; }
  if [ -z "$(apple_gptk_crossover)" ]; then
    aviso "Esta versão do CrossOver.app não tem a pasta apple_gptk — nada a aplicar aqui."
    aviso "Os jogos Steam usam o runner do NotProton (opção 4), que já recebe o GPTK."
    find /Applications/CrossOver.app/Contents -type d -name D3DMetal.framework -prune 2>/dev/null \
      | sed 's/^/     D3DMetal encontrado em: /'
    return 1
  fi
  aplica_gptk "$(apple_gptk_crossover)" crossover-app \
    || aviso "\"Operation not permitted\"? Ajustes > Privacidade e Segurança > Gerenciamento de Apps → liberar o Terminal."
}

# aplica_pfx [APPID]  (sem APPID = todos os prefixos existentes)
aplica_pfx() {
  tem_build && steam_fechado || return 1
  existe ~/"Library/Application Support/Steam/steamapps/compatdata"/${1:-*}/pfx/drive_c/windows/system32/ \
    || { aviso "Nenhum prefixo encontrado${1:+ para o APPID $1} (o jogo já foi aberto alguma vez?)"; return 1; }
  for p in ~/"Library/Application Support/Steam/steamapps/compatdata"/${1:-*}/pfx/drive_c/windows/system32/; do
    [ -d "$p" ] || continue
    backup_pfx "$p" "$(pasta_backup)/pfx-$(basename "${p%/pfx/drive_c/windows/system32/}")"
    cp -f ~/GPTK/atual/wine/x86_64-windows/*.dll "$p"
    ok "Prefixo $(basename "${p%/pfx/drive_c/windows/system32/}") atualizado"
  done
}

# backup_pfx <system32> <pasta de backup> — guarda só as DLLs que o GPTK vai sobrescrever
backup_pfx() {
  mkdir -p "$2"
  printf '%s
' "$1" > "$2/destino"
  for d in ~/GPTK/atual/wine/x86_64-windows/*.dll; do
    [ -f "$1$(basename "$d")" ] && cp -p "$1$(basename "$d")" "$2/"
  done
}

aplica_tudo() {
  aplica_notproton
  aplica_pfx
  aplica_crossover
}

# ---------- 8. verificar -----------------------------------------------------
verificar() {
  info "Build em uso"
  if [ -e ~/GPTK/atual ]; then ok "~/GPTK/atual → $(readlink ~/GPTK/atual)"; else aviso "Nenhuma"; fi
  info "Builds disponíveis"
  if existe ~/GPTK/[0-9]*/; then
    for v in ~/GPTK/[0-9]*/; do printf '  %s\n' "$(basename "$v")"; done
  else
    aviso "Nenhuma"
  fi
  info "D3DMetal no disco"
  find /Applications ~/Library -name D3DMetal.framework -type d 2>/dev/null | while read -r; do
    printf '  %-12s %s\n' "$(defaults read "$REPLY/Versions/A/Resources/Info.plist" CFBundleShortVersionString 2>/dev/null)" "$REPLY"
  done
  info "D3DMetal em uso (precisa de jogo aberto)"
  pgrep -if wine | xargs -I{} lsof -p {} 2>/dev/null | grep -i D3DMetal | awk '{print $NF}' | sort -u | grep . \
    || aviso "Nenhum jogo rodando"
  info "HUD: opção de inicialização no Steam →  MTL_HUD_ENABLED=1 %command%"
}

# ---------- 9. reverter ------------------------------------------------------
reverter() {
  steam_fechado || return 1
  existe ~/GPTK/backup-*/ || { aviso "Nenhum backup em ~/GPTK."; return 1; }
  info "Backups (mais recente por último):"
  PS3="Qual restaurar? "
  select b in $(ls -1d ~/GPTK/backup-*/ | tail -n 8); do
    [ -n "$b" ] && break
  done
  [ -n "${b:-}" ] || return 1
  ls -1 "$b"
  confirma "Restaurar esses destinos?" || return
  for alvo in "$b"*/; do
    if [ -d "${alvo}apple_gptk" ]; then
      ditto "${alvo}apple_gptk" "$(cat "${alvo}destino")"
    else
      find "$alvo" -name '*.dll' -exec cp -f {} "$(cat "${alvo}destino")" \;
    fi
    ok "Restaurado: $(basename "$alvo")"
  done
}

# ---------- 1. completa ------------------------------------------------------
instalacao_completa() {
  prerequisitos || return 1
  instala_apps || return 1
  [ -e ~/GPTK/atual ] || menu_build || return 1
  confirma "Aplicar o GPTK agora?" && aplica_tudo
}

# ---------- 10. desinstalar --------------------------------------------------
desinstalar() {
  steam_fechado || return 1
  aviso "Isso remove Steam, CrossOver, NotProton, ~/GPTK (builds, backups, este script) e o atalho macgaming."
  [ "$(pergunta "Digite DESINSTALAR para confirmar:")" = "DESINSTALAR" ] || { info "Cancelado."; return 1; }

  command -v brew &>/dev/null || carrega_brew

  if command -v brew &>/dev/null; then
    if confirma "Apagar também os dados dos apps (jogos instalados, saves locais, garrafas do CrossOver, runners do NotProton)?"; then
      for c in notprotonnot/notproton/notproton crossover steam; do
        brew list --cask "${c##*/}" &>/dev/null && brew uninstall --cask --zap "$c" && ok "${c##*/} removido (com dados)"
      done
    else
      for c in notprotonnot/notproton/notproton crossover steam; do
        brew list --cask "${c##*/}" &>/dev/null && brew uninstall --cask "$c" && ok "${c##*/} removido (dados mantidos)"
      done
    fi
    brew untap notprotonnot/notproton &>/dev/null && ok "Tap notprotonnot/notproton removido"
  else
    aviso "brew não encontrado — removendo os apps direto de /Applications"
    rm -rf /Applications/Steam.app /Applications/CrossOver.app /Applications/NotProton.app
  fi

  rm -rf ~/"Library/Application Support/notproton"
  ok "Runners do NotProton removidos"

  sed -i '' -e '/^# MacGaming (GPTK/d' -e '/^alias macgaming=/d' ~/.zshrc 2>/dev/null
  ok "Atalho macgaming removido do ~/.zshrc"

  if confirma "Desinstalar também o Homebrew? (remove TODOS os pacotes instalados por ele)"; then
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)" \
      && sed -i '' '/brew shellenv/d' ~/.zprofile 2>/dev/null && ok "Homebrew removido"
  fi

  rm -rf ~/GPTK
  ok "~/GPTK removido"
  info "Desinstalação concluída. O Rosetta 2 é componente do sistema e foi mantido."
  exit 0
}

# ---------- auto-instalação --------------------------------------------------
# Copia este script para ~/GPTK/MacGaming.sh (atualiza se a versão baixada for diferente),
# libera execução/quarentena e cria o atalho "macgaming" no zsh.
instala_script() {
  if ! cmp -s "$0" ~/GPTK/MacGaming.sh; then
    cp -f "$0" ~/GPTK/MacGaming.sh
    ok "Script copiado para ~/GPTK/MacGaming.sh"
  fi
  chmod 755 ~/GPTK/MacGaming.sh
  xattr -d com.apple.quarantine ~/GPTK/MacGaming.sh 2>/dev/null
  grep -qsF "alias macgaming=" ~/.zshrc \
    || printf "\n# MacGaming (GPTK · CrossOver · NotProton · Steam)\nalias macgaming='~/GPTK/MacGaming.sh'\n" >> ~/.zshrc

  # Executado fora de ~/GPTK (ex.: ~/Downloads) → avisa onde rodar daqui em diante
  if [ "$(cd "$(dirname "$0")" && pwd -P)/$(basename "$0")" != "$(cd ~/GPTK && pwd -P)/MacGaming.sh" ]; then
    printf '\n\033[1;33m'
    cat <<'EOF'
 ┌───────────────────────────────────────────────────────────────┐
 │  O script foi copiado para  ~/GPTK/MacGaming.sh               │
 │                                                               │
 │  Das próximas vezes, execute por este caminho:                │
 │      ~/GPTK/MacGaming.sh                                      │
 │  ou, em um novo Terminal, pelo atalho:                        │
 │      macgaming                                                │
 │                                                               │
 │  O arquivo baixado em ~/Downloads pode ser apagado.           │
 └───────────────────────────────────────────────────────────────┘
EOF
    printf '\033[0m\n'
    [ -t 0 ] && [ -z "${1:-}" ] && pergunta "Enter para continuar…" >/dev/null
  fi
}

# ---------- menu -------------------------------------------------------------
mostra_menu() {
  clear
  cat <<EOF
 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  GPTK · CrossOver · NotProton · Steam
  Build em uso: $(readlink ~/GPTK/atual 2>/dev/null || echo "nenhuma")
 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  1) Instalação completa
  2) Instalar/atualizar apps (Steam, CrossOver, NotProton)
  3) Baixar/instalar build do GPTK (4.0 beta 3 ou DMG local)
  4) Aplicar GPTK no NotProton (jogos Steam)
  5) Aplicar GPTK nos prefixos dos jogos
  6) Aplicar GPTK no CrossOver.app
  7) Aplicar em tudo (4 + 5 + 6)
  8) Verificar versões
  9) Reverter backup
 10) Desinstalar tudo
  0) Sair
 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  QUANDO ATUALIZAR  (feche o Steam e os jogos antes)
  • Nova versão do GPTK      → baixe o DMG e use 3, depois 7
  • NotProton baixou runner  → 4
  • Jogo novo instalado      → abra o jogo uma vez, feche e use 5
  • CrossOver atualizado     → 6
  • Apps (Steam/CrossOver/NotProton) → 2, depois 7
  • Conferir: 8  ·  HUD no Steam: MTL_HUD_ENABLED=1 %command%
  • 1ª abertura após trocar o GPTK demora (Rosetta traduzindo)
 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
}

executa() {
  case "$1" in
    1) instalacao_completa ;;
    2) instala_apps ;;
    3) menu_build ;;
    4) aplica_notproton ;;
    5) aplica_pfx "$(pergunta "APPID [Enter = todos]:")" ;;
    6) aplica_crossover ;;
    7) aplica_tudo ;;
    8) verificar ;;
    9) reverter ;;
    10) desinstalar ;;
    0) exit 0 ;;
    *) erro "Opção inválida: $1" ;;
  esac
}

checa_mac
mkdir -p ~/GPTK
instala_script "${1:-}"
migra_layout

if [ -n "${1:-}" ]; then
  executa "$1"
  exit
fi

while true; do
  mostra_menu
  executa "$(pergunta "Opção:")"
  pergunta $'\nEnter para voltar ao menu…' >/dev/null
done
