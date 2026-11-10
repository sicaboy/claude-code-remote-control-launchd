<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.es.md">Español</a> · <a href="README.pt-BR.md">Português</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <b>Русский</b></p>

<p align="center"><img src="assets/banner.svg" alt="Claude Code Remote Control для macOS: постоянно работающая фоновая служба через launchd" width="100%"></p>

<p align="center">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-green.svg"></a>
  <a href="https://github.com/sicaboy/claude-code-remote-control-launchd/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/sicaboy/claude-code-remote-control-launchd/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="Platform: macOS" src="https://img.shields.io/badge/platform-macOS-lightgrey.svg">
  <img alt="Shell: bash" src="https://img.shields.io/badge/shell-bash-4EAA25.svg">
  <img alt="Open source" src="https://img.shields.io/badge/open%20source-%E2%9D%A4-orange.svg">
  <a href="https://github.com/sicaboy/claude-code-remote-control-launchd/pulls"><img alt="PRs welcome" src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg"></a>
</p>

# Claude Code Remote Control for macOS

Запускает **Remote Control** из [Claude Code](https://code.claude.com) (`claude remote-control`) как постоянно работающую фоновую службу macOS (launchd LaunchAgent). Ваш Mac появляется как **карточка устройства** на вкладке Code в приложении Claude (и на claude.ai/code), так что вы можете в любой момент запускать с телефона новые независимые сеансы, не держа открытым терминал.

Это небольшой LaunchAgent и скрипт-надсмотрщик. Он запускается при входе в систему, перезапускает сервер при завершении и не допускает бесконечных перезапусков.

> Неофициальный проект сообщества, не связан с Anthropic и не одобрен ею.

## Установка (одна команда)

```bash
curl -fsSL https://raw.githubusercontent.com/sicaboy/claude-code-remote-control-launchd/main/install.sh | bash -s -- --workdir ~/projects --name "My Mac"
```

или из клона репозитория:

```bash
git clone https://github.com/sicaboy/claude-code-remote-control-launchd && cd claude-code-remote-control-launchd
./install.sh --workdir ~/projects --name "My Mac"
```

| Параметр | По умолчанию | Значение |
| --- | --- | --- |
| `--workdir DIR` | `~/claude-rc` | Каталог, в котором начинаются сеансы. Должен быть **доверенным** для Claude Code (см. ниже). Не домашний каталог. |
| `--name NAME` | имя Mac | Имя устройства, показываемое в приложении |
| `--capacity N` | `10` | Максимум одновременных сеансов. Простаивающие сеансы тоже занимают место, поэтому при заполнении сервера новые сеансы молча игнорируются. |
| `--spawn MODE` | `same-dir` | `same-dir` (общие файлы) или `worktree` (нужен git-репозиторий) |
| `--keep-awake` | выкл. | Удерживает `caffeinate -s`, пока работает сервер, чтобы Mac не засыпал при питании от сети. Не меняет системные настройки энергопотребления. |

Повторный запуск `install.sh` с новыми параметрами обновляет установку на месте.

**Перед установкой:** войдите в аккаунт (`claude auth login`, аккаунт claude.ai; API-ключи с Remote Control не работают) и один раз отметьте рабочий каталог как доверенный: `cd ~/projects && claude`, подтвердите запрос. Установщик проверит и то и другое и подскажет, что делать.

## Повседневное использование

```bash
./install.sh status        # состояние задачи, настройки, последние строки журнала
tail -f ~/.local/share/claude-code-remote-control/server.log
```

## Удаление (одна команда)

```bash
./uninstall.sh                       # удаляет задачу, скрипт, настройки и журналы
./uninstall.sh --keep-logs           # оставить журналы
# без клонирования:
curl -fsSL https://raw.githubusercontent.com/sicaboy/claude-code-remote-control-launchd/main/install.sh | bash -s -- uninstall
```

Удаление останавливает сервер и сеансы, которые он обслуживает.

## Как это работает

`~/Library/LaunchAgents/io.github.sicaboy.claude-code-remote-control.plist` запускает `claude-code-remote-control.sh` с `RunAtLoad` и `KeepAlive`. В каждом цикле скрипт:

1. ждёт сеть (до 2 мин);
2. проверяет `claude auth status`; если вход не выполнен, записывает способ исправления и ждёт 5 мин, не пытаясь постоянно;
3. притормаживает после 3 запусков за час (по 5 мин за каждый лишний запуск, максимум 30), чтобы неисправный сервер не перезапускался в цикле и не оставлял «призрачные» устройства на телефоне;
4. запускает `claude remote-control --spawn <режим> --capacity <n> --name <имя>` в вашем рабочем каталоге;
5. считает сервер зависшим, если за 150 с не установлено HTTPS-соединение (например, из-за невидимого запроса первого запуска), и перезапускает его;
6. каждые 5 мин пишет пульс в журнал, а при завершении сервера — код выхода и последние строки вывода.

Сначала он удаляет унаследованные переменные `CLAUDE*`, `ANTHROPIC_API_KEY` и `ANTHROPIC_AUTH_TOKEN`, чтобы никогда не подхватить идентичность другого сеанса.

Всё хранится в `~/.local/share/claude-code-remote-control/`. В Системных настройках > Основные > Объекты входа и расширения запись отображается как `claude-code-remote-control.sh` (а не просто `bash`).

## Ограничения и примечания

- **Спящий режим.** Спящий Mac недоступен. Используйте `--keep-awake` (запускает `caffeinate -s` только пока работает сервер и помогает только при питании от сети) или настройте всё сами в параметрах энергосбережения. Этот инструмент никогда не меняет системные настройки энергопотребления. Поведение при закрытой крышке не проверялось.
- **После перезагрузки нужен вход.** LaunchAgent работает внутри выполненного входа; при включённом FileVault и без автоматического входа после перезагрузки нужно один раз войти.
- **Срок действия входа.** Продлевайте его через `claude auth login`, когда он истечёт. Журнал показывает дату окончания при каждом запуске.
- **Перезапуск завершает сеансы.** Перезапуск сервера (или повторный запуск `install.sh`, или удаление) останавливает обслуживаемые им сеансы. Истории остаются на диске.
- Работа зависит от поведения `claude remote-control` в текущих версиях Claude Code; параметры могут измениться.

## Частые вопросы

### Как сделать так, чтобы Claude Code Remote Control работал на Mac постоянно?

Установите этот LaunchAgent. Он запускает `claude remote-control` в фоне, стартует при входе и перезапускает его при завершении, поэтому ваш Mac остаётся доступным как устройство в приложении Claude.

### Продолжит ли `claude remote-control` работать после закрытия терминала или перезагрузки?

Сам по себе нет: это процесс переднего плана, и он сдаётся примерно через 10 минут без сети. Под управлением launchd он перезапускается автоматически и стартует при каждом входе. После перезагрузки с FileVault нужно один раз войти.

### Почему новые сеансы, созданные с телефона, не отвечают?

Вероятно, сервер заполнен: простаивающие сеансы занимают место. Посмотрите `Capacity: n/N` в `server.out`, завершите простаивающие сеансы или переустановите с большим `--capacity`.

### Должен ли Mac оставаться бодрствующим?

Да, спящий Mac недоступен. Установите с `--keep-awake`, чтобы удерживать `caffeinate -s`, пока работает сервер (только при питании от сети), или настройте это в параметрах энергосбережения.

### Как удалить?

Выполните `./uninstall.sh` или однострочную команду curl с `uninstall`. Она удалит LaunchAgent, скрипт, настройки и журналы.

## Разработка

```bash
bash test/test.sh      # smoke tests against a fake `claude`, no network
shellcheck -x -S warning install.sh scripts/claude-code-remote-control.sh test/test.sh
```

## Лицензия

[MIT](LICENSE)
