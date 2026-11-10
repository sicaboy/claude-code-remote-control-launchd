<p align="center"><a href="README.md">English</a> · <b>简体中文</b></p>

<p align="center"><img src="assets/banner.svg" alt="Claude Code Remote Control for macOS：基于 launchd 的常驻后台服务" width="100%"></p>

<p align="center">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-green.svg"></a>
  <a href="https://github.com/sicaboy/claude-code-remote-control-launchd/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/sicaboy/claude-code-remote-control-launchd/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="Platform: macOS" src="https://img.shields.io/badge/platform-macOS-lightgrey.svg">
  <img alt="Shell: bash" src="https://img.shields.io/badge/shell-bash-4EAA25.svg">
  <img alt="Open source" src="https://img.shields.io/badge/open%20source-%E2%9D%A4-orange.svg">
  <a href="https://github.com/sicaboy/claude-code-remote-control-launchd/pulls"><img alt="PRs welcome" src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg"></a>
</p>

# Claude Code Remote Control for macOS

把 [Claude Code](https://code.claude.com) 的 **Remote Control**（`claude remote-control`）做成常驻的 macOS 后台服务（launchd LaunchAgent）。这台 Mac 会作为**设备卡片**出现在 Claude app 的 Code 页（以及 claude.ai/code），你可以随时在手机上新建独立会话，不需要一直开着终端。

它由一个 LaunchAgent 和一个监督脚本组成：登录后自动启动，服务退出时自动重启，并且不会反复抖动重启。

> 非官方社区项目，与 Anthropic 无关联，也未获其认可。

## 安装（一条命令）

```bash
curl -fsSL https://raw.githubusercontent.com/sicaboy/claude-code-remote-control-launchd/main/install.sh | bash -s -- --workdir ~/projects --name "我的 Mac"
```

或者克隆后安装：

```bash
git clone https://github.com/sicaboy/claude-code-remote-control-launchd && cd claude-code-remote-control-launchd
./install.sh --workdir ~/projects --name "我的 Mac"
```

| 选项 | 默认值 | 含义 |
| --- | --- | --- |
| `--workdir DIR` | `~/claude-rc` | 会话启动所在的目录。必须已被 Claude Code **信任**（见下），且不能是主目录。 |
| `--name NAME` | 这台 Mac 的名称 | App 里显示的设备名 |
| `--capacity N` | `10` | 同时运行的会话上限。空闲会话也占名额，满了之后新会话会悄悄没有回应。 |
| `--spawn MODE` | `same-dir` | `same-dir`（共享文件）或 `worktree`（需要 git 仓库） |
| `--keep-awake` | 关闭 | 服务运行期间持有 `caffeinate -s`，接电源时 Mac 不会休眠。不修改任何系统电源设置。 |

带着新选项重新运行 `install.sh` 会原地更新安装。

**安装前：**先登录（`claude auth login`，需要 claude.ai 账号，API key 不支持 Remote Control），并让 Claude Code 信任工作目录一次：`cd ~/projects && claude`，接受提示。安装器会检查这两项，并告诉你怎么处理。

## 日常使用

```bash
./install.sh status        # 任务状态、配置、最近的日志
tail -f ~/.local/share/claude-code-remote-control/server.log
```

## 卸载（一条命令）

```bash
./uninstall.sh                       # 删除任务、脚本、配置和日志
./uninstall.sh --keep-logs           # 保留日志
# 没有克隆仓库时：
curl -fsSL https://raw.githubusercontent.com/sicaboy/claude-code-remote-control-launchd/main/install.sh | bash -s -- uninstall
```

卸载会停止服务，以及它正在服务的会话。

## 工作原理

`~/Library/LaunchAgents/io.github.sicaboy.claude-code-remote-control.plist` 以 `RunAtLoad` 和 `KeepAlive` 运行 `claude-code-remote-control.sh`。每个周期脚本会：

1. 等待网络（最多 2 分钟）；
2. 检查 `claude auth status`；若已登出，记录修复方法并暂停 5 分钟，不会反复重试；
3. 1 小时内启动达到 3 次后退避（每多一次加 5 分钟，上限 30 分钟），避免服务抖动，在手机上留下幽灵设备；
4. 在工作目录运行 `claude remote-control --spawn <模式> --capacity <n> --name <名称>`；
5. 150 秒内没有建立 HTTPS 连接就视为卡住（例如看不见的首次运行提示），并重启；
6. 每 5 分钟写一条心跳日志；服务退出时记录退出码和最后几行输出。

脚本会先清除继承来的 `CLAUDE*`、`ANTHROPIC_API_KEY` 和 `ANTHROPIC_AUTH_TOKEN` 环境变量，因此不会沿用其他会话的身份。

所有文件都在 `~/.local/share/claude-code-remote-control/`。在「系统设置 > 通用 > 登录项与扩展」里，它显示为 `claude-code-remote-control.sh`，而不是一个叫 `bash` 的条目。

## 限制与说明

- **睡眠。**Mac 休眠时无法连接。可用 `--keep-awake`（仅在服务运行期间执行 `caffeinate -s`，只在接电源时有效），或自己在节能设置里处理。本工具不会修改系统电源设置。合盖时的行为未验证。
- **重启后需要登录。**LaunchAgent 运行在已登录的会话里；开了 FileVault 又没有自动登录时，重启后需要先登录一次。
- **登录过期。**到期后用 `claude auth login` 续期。日志在每次启动时会记录到期日。
- **重启会结束会话。**重启服务（包括重新运行 `install.sh` 或卸载）会停止它正在服务的会话，对话记录仍保留在磁盘上。
- 它依赖当前 Claude Code 版本中 `claude remote-control` 的行为，参数以后可能变化。

## 开发

```bash
bash test/test.sh      # 用假的 `claude` 做冒烟测试，不联网
shellcheck -x -S warning install.sh scripts/claude-code-remote-control.sh test/test.sh
```

## 许可证

[MIT](LICENSE)
