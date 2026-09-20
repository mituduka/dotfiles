# dotfiles

macOS / Ubuntu / Arch Linux の CLI 環境を 1 コマンドで揃えるための設定をまとめてある。設定の管理には [chezmoi](https://www.chezmoi.io/) を使う。

| 対象 | 状態 |
| --- | --- |
| macOS | Apple Silicon のみ (Intel Mac は非対応) |
| Ubuntu / Debian | Ubuntu 26.04 LTS と 22.04 LTS で検証 |
| Arch Linux | pacman で検証 |
| WSL2 | Ubuntu と同じ手順 (フォントの設定だけ非対応) |
| アーキテクチャ | x86_64 / aarch64 |

zsh、CLI ツール一式、プロンプト、tmux、フォント、git の設定が入る。テキストエディタとブラウザは扱わない。

AI コーディングエージェント (Claude Code / Codex CLI / GitHub Copilot CLI)、Node.js、自作の zsh 関数は任意である。`chezmoi init` のときに 1 つずつ聞かれ、yes と答えたものだけが入る。

| ドキュメント | 内容 |
| --- | --- |
| [docs/commands.md](docs/commands.md) | 入る CLI ツールの使い方 (`eza` `fd` `rg` `uv` など) |
| [docs/shell.md](docs/shell.md) | zsh の略語・補完・履歴・fzf のキーバインド |
| [docs/tmux.md](docs/tmux.md) | tmux のキーバインドとプラグイン |
| [docs/chezmoi.md](docs/chezmoi.md) | 設定を足す、ツールを追加する、他のマシンへ配る |
| [docs/design.md](docs/design.md) | なぜこの構成なのか。つまずいた点と旧構成からの移行 |

## セットアップ

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply mituduka
```

- `curl` さえあれば動く

すでに zsh の設定があるマシンでは、上の 1 行を実行してはいけない。`~/.zshrc` は確認なしでシンボリックリンクに置き換わる。chezmoi が上書き前に確認するのは「以前 chezmoi 自身が書いたファイル」だけで、それ以外は黙って置き換わる。取得と適用を分けて、何が書き換わるかを先に見る。

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init mituduka   # 取得だけして適用しない
chezmoi diff                                            # 差分を確認する
chezmoi apply                                           # 反映する
```

`apply` が途中で失敗したら、必ずもう一度実行する。chezmoi はターゲットのパス順に適用し、失敗するとそこで止まるので、後ろのものが置かれないまま終わる。`~/.zshenv` は名前の順でほぼ最後に来るため、たとえばダウンロードが 1 つ落ちただけでも「CLI ツールは入ったのにシェルの設定が一切効かない」という状態になりうる。

### 初回に聞かれること

`chezmoi init` を実行したときに一度だけ聞かれる。答えた内容は `~/.config/chezmoi/chezmoi.toml` に保存される。

| プロンプト | 既定 | 内容 |
| --- | --- | --- |
| `ヘッドレス環境ですか (フォントとターミナル設定を入れない)` | 環境による | yes ならフォントとターミナル設定を入れない。macOS では聞かれない |
| `Git user.name` | なし | コミットの作者名 |
| `Git user.email` | なし | コミットの作者メールアドレス |
| `Claude Code を入れますか` | no | 公式インストールスクリプトで `~/.local/bin/claude` に入れる |
| `Codex CLI を入れますか` | no | 公式インストールスクリプトで `~/.local/bin/codex` に入れる |
| `GitHub Copilot CLI を入れますか` | no | 公式インストールスクリプトで `~/.local/bin/copilot` に入れる |
| `Node.js を入れますか (fnm でバージョンを管理する)` | no | 既定は LTS の v24 系。`node` `npm` `npx` が入る |
| `自作の zsh 関数を入れますか (yazi 連携の y など)` | yes | `~/.config/zsh/functions/` に置き、`autoload` で読む |

下の 5 つが任意のセットアップである。既定を no にしてあるのは、どれも本体をネットワークから取ってくるものだからで、明示的に yes と答えたものだけが入る。`自作の zsh 関数` だけは外から何も取ってこないので既定を yes にしてある。

ヘッドレスかどうかの既定値は `DISPLAY` と `WAYLAND_DISPLAY` の有無から決めている。ただし SSH 越しに入ると GUI のマシンでも両方とも空になってしまうので、既定値を示したうえで確認するようにした。ここで yes と答えると、フォント、Ghostty の設定、`fc-cache`、`fontconfig` とターミナルエミュレータの導入を省く。シェルや CLI ツールの中身は変わらない。WSL2 では `DISPLAY` が設定されていてもヘッドレス扱いを既定にする (端末は Windows 側のものを使うため)。

答えを変えたくなったら、設定ファイルを書き換えて適用し直す。

```sh
chezmoi edit-config
chezmoi apply
```

すでに使っているマシンでは、このリポジトリを更新しても新しく増えたプロンプトが勝手に出てくることはない。`chezmoi init` を実行し直すと、まだ答えていないものだけを聞いてくる。既に答えた分は聞き直されない。

```sh
chezmoi init      # 増えたプロンプトにだけ答える
chezmoi apply
```

これをしないあいだは、増えた項目は「入れない」として扱われる。`chezmoi apply` が失敗することはない。例外は `自作の zsh 関数` で、こちらは答えていないマシンでも入る。既に `y` を使っている環境で、`chezmoi init` をやり直すまで消えてしまうのを避けるためである。

`Node.js` と `ヘッドレス環境ですか` の答えを変えたときは、パッケージ導入スクリプトが一度やり直される (この 2 つが導入するパッケージの一覧を変えるため)。Arch ではそこに `pacman -Syu` が含まれるので、全システム更新が走る ([理由](docs/design.md#arch-の全システム更新))。更新したくない時期なら、切り替えるタイミングを選ぶ。

### OS ごとの注意

#### macOS (Apple Silicon)

- Homebrew の導入で一度だけ `sudo` を聞かれる。先に `sudo -v` を通しておくと、途中で入力待ちにならずに済む。
- ログインシェルは既に zsh なので切り替えは起きない。
- Ghostty は cask で入り、設定ファイルも配置される。

#### Ubuntu / Debian

- `curl` が入っていない最小構成のときだけ、先に `sudo apt install -y curl` を実行しておく。
- apt の更新と導入、`/etc/shells` への追記で `sudo` のパスワードを聞かれる。
- 最後にログインシェルが `chsh` で zsh に変わる。ここで聞かれるのは sudo ではなく自分のパスワードで、PAM が確認している。これが効くのはログインし直してからなので、新しいターミナルを開くだけでは変わらない。SSH なら接続し直す。
- 端末を持たない非対話の環境では `chsh` を実行せず、警告だけが出る。あとから `chsh -s "$(command -v zsh)"` を自分で実行する。
- Ghostty には公式の apt パッケージがないので、本体は入らない。設定ファイルだけが `~/.config/ghostty/config` に置かれる。本体がほしければ、[公式の手順](https://ghostty.org/docs/install)にしたがって別途導入する。
- WSL2 でも手順は変わらない。フォントの設定だけが対象外になる。

#### Arch Linux

- `curl` が無ければ先に `sudo pacman -S --needed curl` を実行しておく。
- 途中で `pacman -Syu` による全システム更新が走る。数百のパッケージとカーネルまで上がることがあるので、更新したくない時期には実行しないほうがいい ([理由](docs/design.md#arch-の全システム更新))。
- ほとんどのツールが公式リポジトリに揃っているので、pacman で入らずに GitHub Releases から補うことになるのは `ghq` だけである。ただし取得そのものはディストリを問わず全ツールについて走るので、pacman 版があっても一度はダウンロードされる (使われるのは pacman 版のほう。[理由](docs/design.md#ファイルの置き場と-path-の順序))。GUI 環境なら Ghostty も pacman で入る。

## chezmoi による管理

```sh
chezmoi edit ~/.zshrc     # ソースを編集する
chezmoi diff              # 反映前に差分を見る
chezmoi apply             # 反映する
chezmoi update            # git pull + apply + 外部リソースの更新
chezmoi cd                # ソースリポジトリへ移動する
```

ソースリポジトリは `~/.local/share/chezmoi` に置かれる。ホーム直下の実ファイルを直接書き換えても、次に `apply` したときに上書きされてしまうので、編集するときは `chezmoi edit` を使うか、ソースリポジトリ側で直接いじる。設定を足す手順や他のマシンへ配る手順は [docs/chezmoi.md](docs/chezmoi.md) にまとめた。

## 入るもの

### CLI ツール

従来の Unix コマンドを置き換えるものが入る。元のコマンドも消えないので、これまで書いたスクリプトはそのまま動く。

| 入るもの | 置き換え対象 |
| --- | --- |
| `eza` | `ls` |
| `bat` | `cat` |
| `fd` | `find` |
| `ripgrep` (`rg`) | `grep` |
| `dust` | `du` |
| `bottom` (`btm`) | `top` |
| `sd` | `sed -i` |
| `procs` | `ps` |

置き換えではなく、単体で使うものも入る。

| 入るもの | 用途 |
| --- | --- |
| `fzf` | 候補の絞り込み。履歴検索やファイル選択に使う |
| `ouch` | 圧縮と展開。`tar` のオプションを覚えなくて済む |
| `hyperfine` | コマンドの実行時間を測る |
| `tokei` | コード行数の集計 |
| `yazi` | ファイラ。`y` で起動し、抜けた先のディレクトリへ `cd` する (`y` は任意の zsh 関数) |
| `git-delta` | `git diff` の表示 |
| `gh` | GitHub の操作 |
| `ghq` | clone 先を `~/src` 以下に統一する |
| `jq` | JSON の整形と抽出 |
| `uv` | Python のパッケージと処理系の管理 |
| `direnv` | ディレクトリごとに環境変数を出し入れする |

それぞれの使い方は [docs/commands.md](docs/commands.md) を見てほしい。

### シェル

- zsh を既定のログインシェルにし、設定を `~/.config/zsh` に集約する。
- プラグインは git clone で統一し、`~/.local/share/zsh/plugins` に置く。

| プラグイン | 役割 |
| --- | --- |
| `zsh-syntax-highlighting` | コマンドの正誤を入力中に色分けする |
| `zsh-autosuggestions` | 履歴から続きを薄く提案する |
| `zsh-abbr` | 略語を実コマンドに展開する。履歴には展開後が残る |
| `zoxide` | `z <部分一致>` で頻度順にディレクトリを飛ぶ |
| `fzf` | Ctrl-R 履歴検索 / Ctrl-T ファイル選択 / Alt-C ディレクトリ移動 |

略語は `dot_config/zsh-abbr/user-abbreviations` で定義している。キーバインドと履歴の挙動については [docs/shell.md](docs/shell.md) に書いた。

### そのほか

| 項目 | 内容 |
| --- | --- |
| プロンプト | Starship の Gruvbox Rainbow preset |
| フォント | HackGenConsoleNF (GUI 環境のみ)。Ghostty の `font-family` で指定 |
| クイックターミナル | Ghostty の設定で `Ctrl+Enter` に割り当ててある。**OS 全体のホットキー**なので、他のアプリでも `Ctrl+Enter` が Ghostty に取られる。要らなければ `~/.config/ghostty/config` の `keybind = global:...` の行を消す |
| tmux | prefix は `Ctrl-j`。キーバインドは [docs/tmux.md](docs/tmux.md) |
| Claude Code Skills | 日本語ライティング用の 2 つを `~/.claude/skills/` に配置。Gist のリビジョンで固定してあり、更新は手動 ([手順](docs/chezmoi.md#外部アセットの更新)) |
| Python | `uv` に一本化している。pyenv や venv は使わない |

### 任意で入るもの

`chezmoi init` で yes と答えたものだけが入る。

| 項目 | 内容 |
| --- | --- |
| Claude Code | `claude`。起動するとブラウザで認証に進む |
| Codex CLI | `codex`。`codex login` で ChatGPT アカウントか API キーを渡す |
| GitHub Copilot CLI | `copilot`。起動して `/login` と打つ |
| Node.js | `fnm` で管理する。既定は LTS の v24 系。`node` `npm` `npx` が入る |
| 自作の zsh 関数 | `~/.config/zsh/functions/` の中身。いまは yazi 連携の `y` だけ |

エージェント 3 つは提供元の公式インストールスクリプトで入れている。どれも `~/.local/bin` に入るので sudo が要らず、3 OS で手順が同じになり、更新の経路が本体側に閉じる (`claude` と `codex` は自動、`copilot` は `copilot update` を自分で打つ)。パッケージマネージャを使わなかった理由は [docs/design.md](docs/design.md#ai-エージェントの入れ方) に書いた。認証はどれも対話でしかできないので、セットアップでは行わない。

Node.js のバージョン管理に `nvm` ではなく `fnm` を使っている。非対話シェルから `node` を見つけられるようにするうえで差が出る ([理由](docs/design.md#nodejs-を-fnm-で入れる))。

## 旧構成からの移行

新しいマシンに入れる場合、この節は読まなくてよい。

`~/.gitconfig` と `~/.zprofile` は手で消す必要がある。`~/.local/bin` に置いていた GitHub Releases 由来のバイナリは移行スクリプトが片付けてくれる (Linux のみ。macOS では走らないので自分で確認する)。ただし同じ名前で自分が入れたものまで消えることがある。詳しくは [docs/design.md](docs/design.md#旧構成からの移行) に書いた。

pyenv や miniforge が残っているなら、撤去するスクリプトを同梱してある。これは自動では実行しないので、何が消えるかを確認してから手で実行する。

```sh
DRY_RUN=1 ~/.local/bin/cleanup-python.sh   # 消える対象を一覧するだけ
~/.local/bin/cleanup-python.sh             # 確認プロンプトを挟んで実行する
```
