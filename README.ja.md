<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <b>日本語</b> · <a href="README.ko.md">한국어</a> · <a href="README.es.md">Español</a> · <a href="README.pt-BR.md">Português</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.ru.md">Русский</a></p>

<p align="center"><img src="assets/banner.svg" alt="Claude Code Remote Control for macOS：launchd による常駐バックグラウンドサービス" width="100%"></p>

<p align="center">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-green.svg"></a>
  <a href="https://github.com/sicaboy/claude-code-remote-control-launchd/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/sicaboy/claude-code-remote-control-launchd/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="Platform: macOS" src="https://img.shields.io/badge/platform-macOS-lightgrey.svg">
  <img alt="Shell: bash" src="https://img.shields.io/badge/shell-bash-4EAA25.svg">
  <img alt="Open source" src="https://img.shields.io/badge/open%20source-%E2%9D%A4-orange.svg">
  <a href="https://github.com/sicaboy/claude-code-remote-control-launchd/pulls"><img alt="PRs welcome" src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg"></a>
</p>

# Claude Code Remote Control for macOS

[Claude Code](https://code.claude.com) の **Remote Control**（`claude remote-control`）を、macOS の常駐バックグラウンドサービス（launchd LaunchAgent）として動かします。お使いの Mac が Claude アプリの Code タブ（および claude.ai/code）に**デバイスカード**として表示され、ターミナルを開いたままにしなくても、スマートフォンからいつでも独立した新しいセッションを開始できます。

小さな LaunchAgent と監視スクリプトで構成されています。ログイン時に起動し、サーバーが終了したら再起動し、再起動を繰り返す状態（フラッピング）にならないよう制御します。

> 非公式のコミュニティプロジェクトです。Anthropic との提携・承認はありません。

## インストール（コマンド 1 つ）

```bash
curl -fsSL https://raw.githubusercontent.com/sicaboy/claude-code-remote-control-launchd/main/install.sh | bash -s -- --workdir ~/projects --name "My Mac"
```

クローンしてインストールする場合：

```bash
git clone https://github.com/sicaboy/claude-code-remote-control-launchd && cd claude-code-remote-control-launchd
./install.sh --workdir ~/projects --name "My Mac"
```

| オプション | デフォルト | 説明 |
| --- | --- | --- |
| `--workdir DIR` | `~/claude-rc` | セッションを開始するディレクトリ。Claude Code に**信頼**されている必要があります（下記参照）。ホームディレクトリは不可。 |
| `--name NAME` | Mac の名前 | アプリに表示されるデバイス名 |
| `--capacity N` | `10` | 同時セッション数の上限。アイドル中のセッションも枠を占有するため、満杯になると新しいセッションは無反応になります。 |
| `--spawn MODE` | `same-dir` | `same-dir`（ファイル共有）または `worktree`（git リポジトリが必要） |
| `--keep-awake` | オフ | サーバー稼働中は `caffeinate -s` を保持し、電源接続時に Mac がスリープしないようにします。システムの電源設定は変更しません。 |

新しいオプションで `install.sh` を再実行すると、その場で更新されます。

**インストール前に：**サインイン済みであること（`claude auth login`、claude.ai アカウント。Remote Control は API キーでは動きません）、そして作業ディレクトリを一度信頼しておくこと：`cd ~/projects && claude` を実行してプロンプトを承認します。インストーラーが両方を確認し、対処方法を案内します。

## 日常の使い方

```bash
./install.sh status        # ジョブの状態、設定、最新のログ
tail -f ~/.local/share/claude-code-remote-control/server.log
```

## アンインストール（コマンド 1 つ）

```bash
./uninstall.sh                       # ジョブ、スクリプト、設定、ログを削除
./uninstall.sh --keep-logs           # ログを残す
# クローンなしの場合：
curl -fsSL https://raw.githubusercontent.com/sicaboy/claude-code-remote-control-launchd/main/install.sh | bash -s -- uninstall
```

アンインストールすると、サーバーと、それが処理中のセッションが停止します。

## 仕組み

`~/Library/LaunchAgents/io.github.sicaboy.claude-code-remote-control.plist` が `RunAtLoad` と `KeepAlive` で `claude-code-remote-control.sh` を実行します。スクリプトは各サイクルで次を行います。

1. ネットワークを待機します（最大 2 分）。
2. `claude auth status` を確認します。サインアウトしている場合は対処法をログに書き、連打せずに 5 分待機します。
3. 1 時間に 3 回起動したらバックオフします（超過 1 回ごとに 5 分、最大 30 分）。壊れたサーバーが再起動を繰り返し、スマートフォンに幽霊デバイスを残すのを防ぎます。
4. 作業ディレクトリで `claude remote-control --spawn <モード> --capacity <n> --name <名前>` を実行します。
5. 150 秒以内に HTTPS 接続が確立されない場合は停止（例：見えない初回プロンプト）とみなし、再起動します。
6. 5 分ごとにハートビートをログに記録し、サーバー終了時には終了コードと出力の末尾を記録します。

最初に、継承された `CLAUDE*`、`ANTHROPIC_API_KEY`、`ANTHROPIC_AUTH_TOKEN` 環境変数を消去するため、他のセッションの ID を引き継ぎません。

すべて `~/.local/share/claude-code-remote-control/` にあります。システム設定 > 一般 > ログイン項目と拡張機能では、`bash` ではなく `claude-code-remote-control.sh` として表示されます。

## 制限と注意点

- **スリープ。**スリープ中の Mac には接続できません。`--keep-awake`（サーバー稼働中のみ `caffeinate -s` を実行。電源接続時のみ有効）を使うか、省エネルギー設定で自分で管理してください。このツールはシステムの電源設定を変更しません。蓋を閉じた状態での動作は未検証です。
- **再起動後はログインが必要。**LaunchAgent はログイン済みセッション内で動きます。FileVault が有効で自動ログインがない場合は、再起動後に一度ログインしてください。
- **サインインの有効期限。**期限が切れたら `claude auth login` で更新してください。ログには起動のたびに期限日が記録されます。
- **再起動するとセッションが終了します。**サーバーの再起動（`install.sh` の再実行やアンインストールを含む）は、処理中のセッションを停止します。会話の記録はディスクに残ります。
- 現行の Claude Code における `claude remote-control` の挙動に依存しており、フラグは今後変わる可能性があります。

## FAQ

### Mac で Claude Code Remote Control を常時動かし続けるには？

この LaunchAgent をインストールしてください。`claude remote-control` をバックグラウンドで実行し、ログイン時に起動、終了時に再起動するので、Mac は Claude アプリのデバイスとして使える状態を保ちます。

### ターミナルを閉じたり再起動したりしても `claude remote-control` は動き続けますか？

単体では動き続けません。フォアグラウンドのプロセスで、ネットワークが約 10 分途切れると終了します。launchd の管理下では自動で再起動し、ログインのたびに起動します。FileVault が有効な場合、再起動後に一度ログインが必要です。

### スマートフォンから作った新しいセッションが反応しないのはなぜ？

サーバーが満杯の可能性が高いです。アイドルのセッションも枠を占有します。`server.out` の `Capacity: n/N` を確認し、アイドルのセッションを終了するか、`--capacity` を大きくして再インストールしてください。

### Mac は起きたままにする必要がありますか？

はい。スリープ中の Mac には接続できません。`--keep-awake` を付けてインストールすると、サーバー稼働中は `caffeinate -s` を保持します（電源接続時のみ）。省エネルギー設定で管理することもできます。

### アンインストールするには？

`./uninstall.sh` を実行するか、curl のワンライナーに `uninstall` を付けます。LaunchAgent、スクリプト、設定、ログが削除されます。

## 開発

```bash
bash test/test.sh      # smoke tests against a fake `claude`, no network
shellcheck -x -S warning install.sh scripts/claude-code-remote-control.sh test/test.sh
```

## ライセンス

[MIT](LICENSE)
