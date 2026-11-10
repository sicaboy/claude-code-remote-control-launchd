<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <b>한국어</b> · <a href="README.es.md">Español</a> · <a href="README.pt-BR.md">Português</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.ru.md">Русский</a></p>

<p align="center"><img src="assets/banner.svg" alt="Claude Code Remote Control for macOS: launchd 기반 상시 실행 백그라운드 서비스" width="100%"></p>

<p align="center">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-green.svg"></a>
  <a href="https://github.com/sicaboy/claude-code-remote-control-launchd/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/sicaboy/claude-code-remote-control-launchd/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="Platform: macOS" src="https://img.shields.io/badge/platform-macOS-lightgrey.svg">
  <img alt="Shell: bash" src="https://img.shields.io/badge/shell-bash-4EAA25.svg">
  <img alt="Open source" src="https://img.shields.io/badge/open%20source-%E2%9D%A4-orange.svg">
  <a href="https://github.com/sicaboy/claude-code-remote-control-launchd/pulls"><img alt="PRs welcome" src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg"></a>
</p>

# Claude Code Remote Control for macOS

[Claude Code](https://code.claude.com)의 **Remote Control**(`claude remote-control`)을 항상 켜져 있는 macOS 백그라운드 서비스(launchd LaunchAgent)로 실행합니다. 내 Mac이 Claude 앱의 Code 탭(및 claude.ai/code)에 **디바이스 카드**로 나타나므로, 터미널을 열어 두지 않아도 휴대폰에서 언제든 독립된 새 세션을 시작할 수 있습니다.

작은 LaunchAgent와 감시 스크립트로 이루어져 있습니다. 로그인 시 시작하고, 서버가 종료되면 다시 시작하며, 재시작이 반복되는 플래핑은 막습니다.

> 비공식 커뮤니티 프로젝트이며 Anthropic과 제휴하거나 승인을 받지 않았습니다.

## 설치 (명령 한 줄)

```bash
curl -fsSL https://raw.githubusercontent.com/sicaboy/claude-code-remote-control-launchd/main/install.sh | bash -s -- --workdir ~/projects --name "My Mac"
```

저장소를 클론해서 설치하려면:

```bash
git clone https://github.com/sicaboy/claude-code-remote-control-launchd && cd claude-code-remote-control-launchd
./install.sh --workdir ~/projects --name "My Mac"
```

| 옵션 | 기본값 | 설명 |
| --- | --- | --- |
| `--workdir DIR` | `~/claude-rc` | 세션이 시작되는 디렉터리. Claude Code가 **신뢰**하는 디렉터리여야 합니다(아래 참고). 홈 디렉터리는 사용할 수 없습니다. |
| `--name NAME` | Mac의 이름 | 앱에 표시되는 디바이스 이름 |
| `--capacity N` | `10` | 동시 세션 최대 수. 유휴 세션도 자리를 차지하므로, 가득 차면 새 세션은 조용히 무시됩니다. |
| `--spawn MODE` | `same-dir` | `same-dir`(파일 공유) 또는 `worktree`(git 저장소 필요) |
| `--keep-awake` | 꺼짐 | 서버가 실행되는 동안 `caffeinate -s`를 유지해 전원 어댑터 연결 시 Mac이 잠자기에 들어가지 않게 합니다. 시스템 전원 설정은 바꾸지 않습니다. |

새 옵션으로 `install.sh`를 다시 실행하면 설치가 그 자리에서 업데이트됩니다.

**설치 전에:** 로그인되어 있어야 하고(`claude auth login`, claude.ai 계정. Remote Control은 API 키로는 동작하지 않습니다), 작업 디렉터리를 한 번 신뢰해야 합니다. `cd ~/projects && claude`를 실행하고 안내를 수락하세요. 설치 프로그램이 두 가지를 확인하고 해야 할 일을 알려 줍니다.

## 일상적인 사용

```bash
./install.sh status        # 작업 상태, 설정, 최근 로그
tail -f ~/.local/share/claude-code-remote-control/server.log
```

## 제거 (명령 한 줄)

```bash
./uninstall.sh                       # 작업, 스크립트, 설정, 로그 삭제
./uninstall.sh --keep-logs           # 로그는 남김
# 클론 없이:
curl -fsSL https://raw.githubusercontent.com/sicaboy/claude-code-remote-control-launchd/main/install.sh | bash -s -- uninstall
```

제거하면 서버와, 서버가 처리 중이던 세션이 중지됩니다.

## 동작 방식

`~/Library/LaunchAgents/io.github.sicaboy.claude-code-remote-control.plist`가 `RunAtLoad`와 `KeepAlive`로 `claude-code-remote-control.sh`를 실행합니다. 스크립트는 매 주기마다 다음을 수행합니다.

1. 네트워크를 기다립니다(최대 2분).
2. `claude auth status`를 확인합니다. 로그아웃 상태면 해결 방법을 로그에 남기고 계속 시도하는 대신 5분간 대기합니다.
3. 1시간 안에 3번 시작하면 백오프합니다(초과 1회당 5분, 최대 30분). 고장 난 서버가 계속 재시작되어 휴대폰에 유령 디바이스를 남기는 일을 막습니다.
4. 작업 디렉터리에서 `claude remote-control --spawn <모드> --capacity <n> --name <이름>`을 실행합니다.
5. 150초 안에 HTTPS 연결이 맺어지지 않으면 멈춘 것으로 보고(예: 보이지 않는 첫 실행 프롬프트) 다시 시작합니다.
6. 5분마다 하트비트를 기록하고, 서버가 종료되면 종료 코드와 마지막 출력 줄을 기록합니다.

먼저 상속된 `CLAUDE*`, `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN` 환경 변수를 지우므로 다른 세션의 신원을 이어받지 않습니다.

모든 파일은 `~/.local/share/claude-code-remote-control/`에 있습니다. 시스템 설정 > 일반 > 로그인 항목 및 확장 프로그램에서 `bash`가 아닌 `claude-code-remote-control.sh`로 표시됩니다.

## 제한 사항 및 참고

- **잠자기.** 잠자기 중인 Mac에는 연결할 수 없습니다. `--keep-awake`(서버가 실행되는 동안만 `caffeinate -s` 실행, 전원 어댑터 연결 시에만 유효)를 사용하거나, 에너지 설정에서 직접 관리하세요. 이 도구는 시스템 전원 설정을 바꾸지 않습니다. 덮개를 닫았을 때의 동작은 검증하지 않았습니다.
- **재부팅 후 로그인 필요.** LaunchAgent는 로그인된 세션 안에서 실행됩니다. FileVault가 켜져 있고 자동 로그인이 없다면 재부팅 후 한 번 로그인해야 합니다.
- **로그인 만료.** 만료되면 `claude auth login`으로 갱신하세요. 로그에는 시작할 때마다 만료일이 기록됩니다.
- **재시작하면 세션이 종료됩니다.** 서버를 재시작하면(`install.sh` 재실행이나 제거 포함) 처리 중인 세션이 중지됩니다. 대화 기록은 디스크에 남습니다.
- 현재 Claude Code 릴리스의 `claude remote-control` 동작에 의존하므로 플래그는 바뀔 수 있습니다.

## 자주 묻는 질문

### Mac에서 Claude Code Remote Control을 항상 실행해 두려면 어떻게 하나요?

이 LaunchAgent를 설치하세요. `claude remote-control`을 백그라운드에서 실행하고, 로그인 시 시작하며, 종료되면 다시 시작하므로 Mac이 Claude 앱의 디바이스로 계속 유지됩니다.

### 터미널을 닫거나 재부팅해도 `claude remote-control`이 계속 실행되나요?

단독으로는 아닙니다. 포그라운드 프로세스이며 네트워크가 약 10분 끊기면 종료됩니다. launchd 아래에서는 자동으로 다시 시작되고 로그인할 때마다 시작됩니다. FileVault가 켜진 Mac은 재부팅 후 한 번 로그인해야 합니다.

### 휴대폰에서 만든 새 세션에 응답이 없는 이유는 무엇인가요?

서버가 가득 찼을 가능성이 큽니다. 유휴 세션도 자리를 차지합니다. `server.out`의 `Capacity: n/N`을 확인하고, 유휴 세션을 종료하거나 더 큰 `--capacity`로 다시 설치하세요.

### Mac이 계속 깨어 있어야 하나요?

네. 잠자기 중인 Mac에는 연결할 수 없습니다. `--keep-awake`로 설치하면 서버가 실행되는 동안 `caffeinate -s`를 유지합니다(전원 어댑터 연결 시에만). 에너지 설정에서 직접 관리해도 됩니다.

### 어떻게 제거하나요?

`./uninstall.sh`를 실행하거나, curl 한 줄 명령에 `uninstall`을 붙이세요. LaunchAgent, 스크립트, 설정, 로그가 삭제됩니다.

## 개발

```bash
bash test/test.sh      # smoke tests against a fake `claude`, no network
shellcheck -x -S warning install.sh scripts/claude-code-remote-control.sh test/test.sh
```

## 라이선스

[MIT](LICENSE)
