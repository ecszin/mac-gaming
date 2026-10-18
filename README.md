# MacGaming — Steam + CrossOver + NotProton + GPTK no macOS

Script único, com menu interativo, para **instalar, atualizar, verificar, reverter e desinstalar** o conjunto que permite rodar jogos Windows da Steam em Macs com Apple Silicon:

- **[Steam](https://store.steampowered.com/)** — cliente macOS
- **[CrossOver](https://www.codeweavers.com/crossover)** — camada de compatibilidade Windows
- **[NotProton](https://github.com/NotProtonNot/NotProton)** — ativa o Steam Play no Steam do macOS usando o CrossOver como Compatibility Tool
- **[Game Porting Toolkit](https://developer.apple.com/games/game-porting-toolkit/)** (GPTK) — D3DMetal da Apple (DirectX 11/12 → Metal)

O script automatiza o processo manual de copiar o D3DMetal do GPTK para o runner do NotProton, para os prefixos dos jogos e para o CrossOver.app, sempre com backup antes de sobrescrever.

> ⚠️ **Projeto experimental.** GPTK 4 está em beta e o NotProton está em estágio inicial. Use por sua conta e risco.

---

## Requisitos

| Item | Mínimo |
|---|---|
| Mac | Apple Silicon (M1 ou superior) |
| macOS | 27 recomendado (GPTK 4) |
| RAM | 16 GB recomendado |
| Conta | Apple ID (gratuito) para baixar o GPTK |

O **Rosetta 2** e o **Homebrew** são instalados automaticamente se não existirem.

Testado em: MacBook Air M5 · macOS 27.0.1 · CrossOver 26.3 · GPTK 4.0 beta 3.

---

## Instalação

```bash
curl -fsSL -o ~/Downloads/install-gaming-mac.sh \
  https://raw.githubusercontent.com/<usuario>/<repositorio>/main/install-gaming-mac.sh
chmod +x ~/Downloads/install-gaming-mac.sh
~/Downloads/install-gaming-mac.sh
```

Na primeira execução o script:

1. cria a pasta `~/GPTK`;
2. se copia para `~/GPTK/MacGaming.sh` (com permissão de execução e sem quarentena);
3. cria o atalho `macgaming` no `~/.zshrc`.

O arquivo em `~/Downloads` pode ser apagado depois. Daí em diante:

```bash
macgaming          # abre o menu (em um novo Terminal)
macgaming 4        # executa direto uma opção do menu
~/GPTK/MacGaming.sh
```

Em uma instalação do zero, use a **opção 1 (Instalação completa)**.

---

## Menu

```
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
```

| Opção | O que faz |
|---|---|
| **1** | Pré-requisitos → apps → build do GPTK → aplica em tudo |
| **2** | `brew install/upgrade --cask` de `steam`, `crossover` e `notprotonnot/notproton/notproton` |
| **3** | Abre o download do GPTK no navegador (exige login Apple ID), aguarda o DMG em `~/Downloads` e extrai para `~/GPTK/<versão>`. Aceita também um DMG já baixado (pode arrastar o arquivo para o Terminal) |
| **4** | Aplica em **todos** os runners `crossover-*` do NotProton |
| **5** | Copia as DLLs para o `system32` de todos os prefixos (ou de um APPID específico) |
| **6** | Localiza a pasta `apple_gptk` dentro do CrossOver.app e aplica |
| **8** | Mostra a build em uso, versões do D3DMetal no disco e qual está carregado pelo jogo aberto |
| **9** | Lista os últimos backups e restaura o escolhido |
| **10** | Remove apps, runners, `~/GPTK` e o atalho — com confirmação digitada |

---

## Estrutura

```
~/GPTK/
├── MacGaming.sh        # o script (instalado automaticamente)
├── atual -> 4.0b3      # link para a build em uso
├── 4.0b3/              # uma pasta por versão (redist/lib do DMG)
│   ├── external/       # D3DMetal.framework, libd3dshared…
│   └── wine/           # DLLs x86_64-windows / x86_64-unix
└── backup-AAAAMMDD-HHMM/
    ├── notproton-crossover-<versão>/   # apple_gptk original + destino
    ├── pfx-<APPID>/                    # DLLs originais + destino
    └── crossover-app/
```

Trocar de versão do GPTK = instalar a nova build pela opção 3 (o link `atual` passa a apontar para ela) e rodar a opção 7. As versões anteriores continuam em `~/GPTK/<versão>`.

### Onde o GPTK é aplicado

| Destino | Caminho |
|---|---|
| Jogos Steam (NotProton) | `~/Library/Application Support/notproton/runners/crossover-*/CrossOver/lib64/apple_gptk` |
| Prefixos dos jogos | `~/Library/Application Support/Steam/steamapps/compatdata/<APPID>/pfx/drive_c/windows/system32` |
| CrossOver.app | `apple_gptk` localizado dentro de `/Applications/CrossOver.app/Contents` |

---

## Quando atualizar

Feche o Steam e os jogos antes — o script recusa rodar com eles abertos.

| Situação | Opção |
|---|---|
| Nova versão do GPTK | **3**, depois **7** |
| NotProton baixou runner novo | **4** |
| Jogo novo instalado | abra o jogo uma vez, feche e use **5** |
| CrossOver atualizado | **6** |
| Apps atualizados | **2**, depois **7** |

---

## Conferir se está funcionando

- **HUD do Metal** — nas opções de inicialização do jogo no Steam:
  ```
  MTL_HUD_ENABLED=1 %command%
  ```
  O HUD mostra `Game Porting Toolkit X.X`.
- **Opção 8** do menu — versões no disco e D3DMetal carregado pelo jogo em execução.

---

## Solução de problemas

| Sintoma | Solução |
|---|---|
| `Operation not permitted` | Ajustes → Privacidade e Segurança → **Gerenciamento de Apps** e **Acesso Total ao Disco** → liberar o Terminal |
| Primeira abertura do jogo muito lenta | Normal após trocar o GPTK: o Rosetta está traduzindo e gerando cache |
| `event not found` | Não cole o script no Terminal; execute o arquivo |
| Opção 6 diz que não há `apple_gptk` | Essa versão do CrossOver.app não usa a pasta; os jogos Steam dependem só do runner (opção 4) |
| Jogo parou de abrir após aplicar | Opção **9** para restaurar o backup |

---

## Desinstalação

Opção **10** do menu. Remove Steam, CrossOver, NotProton, runners do NotProton, `~/GPTK` e o atalho `macgaming`. Pergunta separadamente se deve apagar os dados dos apps (jogos instalados, saves locais, garrafas) e se deve remover o Homebrew. O Rosetta 2 é mantido (componente do sistema).

---

## Observações legais

- Este projeto **não redistribui** o Game Porting Toolkit. O DMG é baixado diretamente da Apple pelo usuário, sujeito à licença da Apple para o D3DMetal.
- CrossOver é software comercial da CodeWeavers e requer licença após o período de avaliação.
- Projeto independente, sem afiliação com Apple, Valve, CodeWeavers ou NotProton.

## Créditos

- [Apple — Game Porting Toolkit](https://developer.apple.com/games/game-porting-toolkit/)
- [NotProtonNot/NotProton](https://github.com/NotProtonNot/NotProton) e [homebrew-notproton](https://github.com/NotProtonNot/homebrew-notproton)
- [CodeWeavers — CrossOver](https://www.codeweavers.com/crossover)
- [Homebrew](https://brew.sh)
