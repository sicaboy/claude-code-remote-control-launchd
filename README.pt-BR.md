<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.es.md">Español</a> · <b>Português</b> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.ru.md">Русский</a></p>

<p align="center"><img src="assets/banner.svg" alt="Claude Code Remote Control para macOS: serviço em segundo plano sempre ativo com launchd" width="100%"></p>

<p align="center">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-green.svg"></a>
  <a href="https://github.com/sicaboy/claude-code-remote-control-launchd/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/sicaboy/claude-code-remote-control-launchd/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="Platform: macOS" src="https://img.shields.io/badge/platform-macOS-lightgrey.svg">
  <img alt="Shell: bash" src="https://img.shields.io/badge/shell-bash-4EAA25.svg">
  <img alt="Open source" src="https://img.shields.io/badge/open%20source-%E2%9D%A4-orange.svg">
  <a href="https://github.com/sicaboy/claude-code-remote-control-launchd/pulls"><img alt="PRs welcome" src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg"></a>
</p>

# Claude Code Remote Control for macOS

Execute o **Remote Control** do [Claude Code](https://code.claude.com) (`claude remote-control`) como um serviço do macOS sempre ativo em segundo plano (LaunchAgent do launchd). O seu Mac aparece como um **cartão de dispositivo** na aba Code do app do Claude (e em claude.ai/code), então você pode iniciar sessões novas e independentes pelo celular a qualquer momento, sem deixar um terminal aberto.

É um pequeno LaunchAgent mais um script supervisor. Ele inicia no login, reinicia o servidor quando ele termina e evita reinicializações em loop.

> Projeto comunitário não oficial, sem afiliação nem aprovação da Anthropic.

## Instalação (um comando)

```bash
curl -fsSL https://raw.githubusercontent.com/sicaboy/claude-code-remote-control-launchd/main/install.sh | bash -s -- --workdir ~/projects --name "My Mac"
```

ou a partir de um clone do repositório:

```bash
git clone https://github.com/sicaboy/claude-code-remote-control-launchd && cd claude-code-remote-control-launchd
./install.sh --workdir ~/projects --name "My Mac"
```

| Opção | Padrão | Significado |
| --- | --- | --- |
| `--workdir DIR` | `~/claude-rc` | Diretório onde as sessões começam. Precisa ser **confiável** para o Claude Code (veja abaixo). Não pode ser o seu diretório pessoal. |
| `--name NAME` | o nome do Mac | Nome do dispositivo exibido no app |
| `--capacity N` | `10` | Máximo de sessões simultâneas. Sessões ociosas continuam ocupando a vaga, então, com o servidor cheio, as sessões novas são ignoradas em silêncio. |
| `--spawn MODE` | `same-dir` | `same-dir` (arquivos compartilhados) ou `worktree` (exige um repositório git) |
| `--keep-awake` | desligado | Mantém `caffeinate -s` enquanto o servidor roda, para o Mac não entrar em repouso com o carregador conectado. Não altera nenhuma configuração de energia do sistema. |

Executar `install.sh` de novo com outras opções atualiza a instalação no lugar.

**Antes de instalar:** esteja conectado (`claude auth login`, com uma conta claude.ai; chaves de API não funcionam com o Remote Control) e marque o diretório de trabalho como confiável uma vez: `cd ~/projects && claude` e aceite o aviso. O instalador verifica as duas coisas e diz o que fazer.

## Uso diário

```bash
./install.sh status        # estado do job, configuração e últimas linhas do log
tail -f ~/.local/share/claude-code-remote-control/server.log
```

## Desinstalação (um comando)

```bash
./uninstall.sh                       # remove o job, o script, a configuração e os logs
./uninstall.sh --keep-logs           # mantém os logs
# sem clonar o repositório:
curl -fsSL https://raw.githubusercontent.com/sicaboy/claude-code-remote-control-launchd/main/install.sh | bash -s -- uninstall
```

Desinstalar interrompe o servidor e as sessões que ele atende.

## Como funciona

`~/Library/LaunchAgents/io.github.sicaboy.claude-code-remote-control.plist` executa `claude-code-remote-control.sh` com `RunAtLoad` e `KeepAlive`. A cada ciclo o script:

1. espera pela rede (até 2 min);
2. verifica `claude auth status`; se estiver desconectado, registra a correção e espera 5 min em vez de insistir;
3. aplica um recuo após 3 inicializações em uma hora (5 min por inicialização extra, no máximo 30), para que um servidor com defeito não fique reiniciando e deixe dispositivos fantasma no celular;
4. executa `claude remote-control --spawn <modo> --capacity <n> --name <nome>` no seu diretório de trabalho;
5. considera travado se não houver conexão HTTPS estabelecida em 150 s (por exemplo, um aviso de primeira execução invisível) e reinicia;
6. registra um sinal de vida a cada 5 min e, quando o servidor termina, o código de saída e as últimas linhas de saída.

Antes de tudo, ele limpa as variáveis herdadas `CLAUDE*`, `ANTHROPIC_API_KEY` e `ANTHROPIC_AUTH_TOKEN`, para nunca assumir a identidade de outra sessão.

Tudo fica em `~/.local/share/claude-code-remote-control/`. Em Ajustes do Sistema > Geral > Itens de Login e Extensões, o item aparece como `claude-code-remote-control.sh` (e não como um simples `bash`).

## Limites e observações

- **Repouso.** Um Mac em repouso não é acessível. Use `--keep-awake` (executa `caffeinate -s` só enquanto o servidor roda e só ajuda com o carregador conectado) ou gerencie você mesmo nas configurações de energia. Esta ferramenta nunca altera as configurações de energia do sistema. O comportamento com a tampa fechada não foi verificado.
- **É preciso fazer login após reiniciar.** Um LaunchAgent roda dentro de uma sessão com login feito; com FileVault e sem login automático, faça login uma vez após reiniciar.
- **Expiração do login.** Renove com `claude auth login` quando expirar. O log mostra a data de expiração a cada inicialização.
- **Reiniciar encerra as sessões.** Reiniciar o servidor (ou executar `install.sh` de novo, ou desinstalar) interrompe as sessões que ele atende. As transcrições ficam no disco.
- Depende do comportamento de `claude remote-control` nas versões atuais do Claude Code; as opções podem mudar.

## Perguntas frequentes

### Como manter o Claude Code Remote Control sempre em execução em um Mac?

Instale este LaunchAgent. Ele executa `claude remote-control` em segundo plano, inicia no login e reinicia quando termina, de modo que o seu Mac continue disponível como dispositivo no app do Claude.

### O `claude remote-control` continua rodando depois de fechar o terminal ou reiniciar?

Sozinho, não: é um processo em primeiro plano e desiste após cerca de 10 minutos sem rede. Sob o launchd ele é reiniciado automaticamente e inicia a cada login. Após reiniciar com FileVault, é preciso fazer login uma vez.

### Por que as sessões novas criadas pelo celular não respondem?

Provavelmente o servidor está cheio: sessões ociosas continuam ocupando a vaga. Veja `Capacity: n/N` em `server.out`, encerre as sessões ociosas ou reinstale com um `--capacity` maior.

### O Mac precisa ficar acordado?

Sim, um Mac em repouso não é acessível. Instale com `--keep-awake` para manter `caffeinate -s` enquanto o servidor roda (só com o carregador conectado) ou configure nas configurações de energia.

### Como desinstalar?

Execute `./uninstall.sh`, ou o comando curl com `uninstall`. Ele remove o LaunchAgent, o script, a configuração e os logs.

## Desenvolvimento

```bash
bash test/test.sh      # smoke tests against a fake `claude`, no network
shellcheck -x -S warning install.sh scripts/claude-code-remote-control.sh test/test.sh
```

## Licença

[MIT](LICENSE)
