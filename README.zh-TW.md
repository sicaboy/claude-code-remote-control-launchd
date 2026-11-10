<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <b>繁體中文</b> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.es.md">Español</a> · <a href="README.pt-BR.md">Português</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.ru.md">Русский</a></p>

<p align="center"><img src="assets/banner.svg" alt="Claude Code Remote Control for macOS：基於 launchd 的常駐背景服務" width="100%"></p>

<p align="center">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-green.svg"></a>
  <a href="https://github.com/sicaboy/claude-code-remote-control-launchd/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/sicaboy/claude-code-remote-control-launchd/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="Platform: macOS" src="https://img.shields.io/badge/platform-macOS-lightgrey.svg">
  <img alt="Shell: bash" src="https://img.shields.io/badge/shell-bash-4EAA25.svg">
  <img alt="Open source" src="https://img.shields.io/badge/open%20source-%E2%9D%A4-orange.svg">
  <a href="https://github.com/sicaboy/claude-code-remote-control-launchd/pulls"><img alt="PRs welcome" src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg"></a>
</p>

# Claude Code Remote Control for macOS

把 [Claude Code](https://code.claude.com) 的 **Remote Control**（`claude remote-control`）做成常駐的 macOS 背景服務（launchd LaunchAgent）。這台 Mac 會以**裝置卡片**的形式出現在 Claude app 的 Code 分頁（以及 claude.ai/code），你可以隨時在手機上建立新的獨立工作階段，不必一直開著終端機。

它由一個 LaunchAgent 和一支監督腳本組成：登入後自動啟動，服務結束時自動重啟，而且不會反覆震盪重啟。

> 非官方社群專案，與 Anthropic 無關聯，亦未獲其背書。

## 安裝（一行指令）

```bash
curl -fsSL https://raw.githubusercontent.com/sicaboy/claude-code-remote-control-launchd/main/install.sh | bash -s -- --workdir ~/projects --name "My Mac"
```

或是複製儲存庫後安裝：

```bash
git clone https://github.com/sicaboy/claude-code-remote-control-launchd && cd claude-code-remote-control-launchd
./install.sh --workdir ~/projects --name "My Mac"
```

| 選項 | 預設值 | 說明 |
| --- | --- | --- |
| `--workdir DIR` | `~/claude-rc` | 工作階段啟動所在的目錄。必須已被 Claude Code **信任**（見下），且不能是家目錄。 |
| `--name NAME` | 這台 Mac 的名稱 | App 中顯示的裝置名稱 |
| `--capacity N` | `10` | 同時執行的工作階段上限。閒置的工作階段也佔名額，額滿後新的工作階段會悄悄沒有回應。 |
| `--spawn MODE` | `same-dir` | `same-dir`（共用檔案）或 `worktree`（需要 git 儲存庫） |
| `--keep-awake` | 關閉 | 服務執行期間持有 `caffeinate -s`，接上電源時 Mac 不會休眠。不會修改任何系統電源設定。 |

帶著新選項重新執行 `install.sh` 會就地更新安裝。

**安裝前：**先登入（`claude auth login`，需要 claude.ai 帳號，API key 不支援 Remote Control），並讓 Claude Code 信任工作目錄一次：`cd ~/projects && claude`，接受提示。安裝程式會檢查這兩項，並告訴你怎麼處理。

## 日常使用

```bash
./install.sh status        # 任務狀態、設定、最近的日誌
tail -f ~/.local/share/claude-code-remote-control/server.log
```

## 解除安裝（一行指令）

```bash
./uninstall.sh                       # 移除任務、腳本、設定與日誌
./uninstall.sh --keep-logs           # 保留日誌
# 沒有複製儲存庫時：
curl -fsSL https://raw.githubusercontent.com/sicaboy/claude-code-remote-control-launchd/main/install.sh | bash -s -- uninstall
```

解除安裝會停止服務，以及它正在服務的工作階段。

## 運作方式

`~/Library/LaunchAgents/io.github.sicaboy.claude-code-remote-control.plist` 以 `RunAtLoad` 與 `KeepAlive` 執行 `claude-code-remote-control.sh`。每個週期腳本會：

1. 等待網路（最多 2 分鐘）；
2. 檢查 `claude auth status`；若已登出，記錄修復方法並暫停 5 分鐘，不會反覆重試；
3. 1 小時內啟動達 3 次後退避（每多一次加 5 分鐘，上限 30 分鐘），避免服務震盪，在手機上留下幽靈裝置；
4. 在工作目錄執行 `claude remote-control --spawn <模式> --capacity <n> --name <名稱>`；
5. 150 秒內沒有建立 HTTPS 連線就視為卡住（例如看不見的首次執行提示），並重啟；
6. 每 5 分鐘寫一筆心跳日誌；服務結束時記錄結束碼與最後幾行輸出。

腳本會先清除繼承而來的 `CLAUDE*`、`ANTHROPIC_API_KEY` 與 `ANTHROPIC_AUTH_TOKEN` 環境變數，因此不會沿用其他工作階段的身分。

所有檔案都在 `~/.local/share/claude-code-remote-control/`。在「系統設定 > 一般 > 登入項目與延伸功能」中，它顯示為 `claude-code-remote-control.sh`，而不是一個叫 `bash` 的項目。

## 限制與說明

- **睡眠。**Mac 休眠時無法連線。可用 `--keep-awake`（僅在服務執行期間執行 `caffeinate -s`，只在接電源時有效），或自行在能源設定中處理。本工具不會修改系統電源設定。闔上螢幕時的行為尚未驗證。
- **重新開機後需要登入。**LaunchAgent 執行於已登入的工作階段中；開啟 FileVault 又沒有自動登入時，重新開機後需先登入一次。
- **登入到期。**到期後用 `claude auth login` 續期。日誌會在每次啟動時記錄到期日。
- **重啟會結束工作階段。**重啟服務（包括重新執行 `install.sh` 或解除安裝）會停止它正在服務的工作階段，對話紀錄仍保留在磁碟上。
- 它依賴目前 Claude Code 版本中 `claude remote-control` 的行為，參數日後可能變動。

## 常見問題

### 如何讓 Claude Code Remote Control 在 Mac 上一直執行？

安裝這個 LaunchAgent。它在背景執行 `claude remote-control`，登入時自動啟動，結束時自動重啟，這台 Mac 就會一直以裝置的身分出現在 Claude app 中。

### 關閉終端機或重新開機後，`claude remote-control` 還會繼續執行嗎？

它本身不會：它是前景程序，斷網約 10 分鐘就會放棄。交給 launchd 後會自動重啟，並在每次登入時啟動。開啟 FileVault 的 Mac 重新開機後需先登入一次。

### 為什麼在手機上建立的新工作階段沒有回應？

多半是服務已額滿：閒置的工作階段也佔名額。查看 `server.out` 中的 `Capacity: n/N`，結束閒置的工作階段，或用較大的 `--capacity` 重新安裝。

### Mac 必須保持喚醒嗎？

是的，休眠的 Mac 無法連線。用 `--keep-awake` 安裝，服務執行期間會持有 `caffeinate -s`（僅限接電源），也可以自行在能源設定中處理。

### 如何解除安裝？

執行 `./uninstall.sh`，或用 curl 一行指令加上 `uninstall`。它會移除 LaunchAgent、腳本、設定與日誌。

## 開發

```bash
bash test/test.sh      # smoke tests against a fake `claude`, no network
shellcheck -x -S warning install.sh scripts/claude-code-remote-control.sh test/test.sh
```

## 授權條款

[MIT](LICENSE)
