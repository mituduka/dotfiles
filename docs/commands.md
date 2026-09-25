# コマンドの使い方

入る CLI ツールについて、これだけ覚えれば従来のコマンドから乗り換えられる、という最小限をまとめる。細かいオプションは各ツールの `--help` で確認してほしい。fzf のキーバインドは [shell.md](shell.md)、tmux の操作は [tmux.md](tmux.md) に分けて書いた。

- [従来コマンドの置き換え](#従来コマンドの置き換え)
- [単体で使うもの](#単体で使うもの)
- [git 関連](#git-関連)
- [Python (uv)](#python-uv)
- [Node.js (fnm)](#nodejs-fnm)
- [Rust (rustup)](#rust-rustup)
- [AI コーディングエージェント](#ai-コーディングエージェント)

## 従来コマンドの置き換え

| 入るもの | 置き換え対象 | 変わる点 |
| --- | --- | --- |
| `eza` | `ls` | git 状態とアイコンが出る |
| `bat` | `cat` | 構文強調と行番号が付く |
| `fd` | `find` | 書き方が短く、既定で `.gitignore` を尊重する |
| `rg` | `grep` | 再帰検索が既定。圧倒的に速い |
| `dust` | `du` | 容量を棒グラフで表示する |
| `btm` | `top` | グラフ付きのリソースモニタ |
| `sd` | `sed -i` | 置換だけに特化。正規表現が直感的 |
| `procs` | `ps` | 検索とツリー表示ができる |

元のコマンドも消えないので、これまで書いたスクリプトはそのまま動く。

### eza (`ls`)

`ls` は `eza -F --icons --git --group-directories-first` の alias にしてある。ディレクトリが先に並び、git の変更状態が右端に出る。この alias は eza が入っている環境でだけ張られるので、入っていなければ本物の `ls` がそのまま使える。ただし略語の `lt` だけは eza 専用の `--tree` を使っているので動かない。

```sh
ls              # 一覧
ll              # ls -l    (略語)
la              # ls -l -A (略語。隠しファイルも)
lt              # ls --tree (略語。ツリー表示)
l               # clear && ls (略語)

ls --tree --level=2      # 深さを制限したツリー
ls -l --sort=modified    # 更新順
ls -l --total-size       # ディレクトリの合計サイズも計算する
```

### bat (`cat`)

```sh
bat file.py              # 構文強調 + 行番号 + ページャ
bat -p file.py           # 装飾なし (cat と同じ見た目)
bat -n file.py           # 行番号だけ
bat -r 20:40 file.py     # 20〜40 行目だけ
bat -A file.txt          # 不可視文字を可視化する (タブ・改行コードの確認に)
```

git 管理下のファイルでは、変更行に印が付く。

### fd (`find`)

`find` と違って、探すパターンを第 1 引数に書く。既定では `.gitignore` に書かれたものと隠しファイルを除外する。

```sh
fd config                # 名前に config を含むものを再帰的に探す
fd '\.py$'               # 正規表現
fd -e py                 # 拡張子で絞る (推奨)
fd -H                    # 隠しファイルも含める
fd -I                    # .gitignore を無視して全部見る
fd -t d src              # ディレクトリだけ (-t f ならファイルだけ)
fd -e log -x rm          # 見つかったものに対してコマンドを実行する
fd -e py -X wc -l        # まとめて 1 回のコマンドに渡す
```

`-x` は 1 件ずつ、`-X` は全件まとめて渡す。

### ripgrep (`grep`)

```sh
rg TODO                  # カレント以下を再帰検索
rg -i todo               # 大文字小文字を無視
rg -w error              # 単語単位で一致
rg -F 'a.b.c'            # 正規表現ではなくリテラルとして扱う
rg TODO -g '*.py'        # ファイル名で絞る
rg TODO -t py            # 言語で絞る (rg --type-list で一覧)
rg -l TODO               # 一致したファイル名だけ
rg -C 3 TODO             # 前後 3 行も表示
rg --hidden --no-ignore  # 隠しファイルと .gitignore 対象も含める
```

置換のプレビューもできる。

```sh
rg 'foo(\d+)' -r 'bar$1'
```

### dust (`du`)

```sh
dust                     # カレント以下を容量順に
dust -d 2                # 深さ 2 まで
dust -r                  # 大きいものを下に (逆順)
dust -n 40               # 表示件数
dust -X node_modules     # 特定のディレクトリを除外
dust -e '\.log$'         # 正規表現で絞る
dust -t                  # ファイル種別ごとに集計
```

### bottom (`top`)

```sh
btm                      # 起動
btm -b                   # グラフなし (basic モード)
```

起動したあとのキー操作は次のとおり。

| キー | 動作 |
| --- | --- |
| `?` | ヘルプ |
| `dd` | プロセスを kill |
| `/` | プロセス検索 |
| `Tab` | 同名プロセスをまとめる |
| `t` | ツリー表示 |
| `q` | 終了 |

### sd (`sed -i`)

既定でファイルを直接書き換えるので、まず `-p` で確認する癖をつけるとよい。

```sh
sd -p 'before' 'after' file.txt      # 変更内容をプレビュー
sd 'before' 'after' file.txt         # 実際に置換 (in-place)
sd -F 'a.b' 'c' file.txt             # リテラル文字列として扱う
sd '(\w+)@(\w+)' '$2@$1' file.txt    # キャプチャは $1 $2
cat file.txt | sd 'a' 'b'            # 標準入力からも読める
fd -e py -X sd 'old_name' 'new_name' # 複数ファイルを一括置換
```

`sed` と違って `s///` も区切り文字のエスケープも要らない。

### procs (`ps`)

```sh
procs                    # 全プロセス
procs zsh                # 名前・コマンドラインで検索
procs --tree             # 親子関係をツリーで
procs --sortd cpu        # CPU 使用率の降順 (--sorta なら昇順)
procs -W 2               # 2 秒ごとに更新し続ける
```

## 単体で使うもの

### hyperfine (ベンチマーク)

コマンドの実行時間を統計的に測る。ウォームアップと複数回試行を自動で行う。

```sh
hyperfine 'zsh -i -c exit'                  # 単体を測る
hyperfine -w 3 'cmd'                        # ウォームアップ 3 回
hyperfine -r 20 'cmd'                       # 試行 20 回
hyperfine 'grep -r foo .' 'rg foo'          # 2 つを比較する
hyperfine -p 'make clean' 'make'            # 各試行の前に準備コマンドを実行
hyperfine -L n 1,2,4,8 'cmd -j {n}'         # パラメータを振って比較
hyperfine --export-markdown out.md 'cmd'    # 結果を書き出す
```

### ouch (圧縮・展開)

形式を意識せずに扱える。`tar` のオプションを覚える必要がない。

```sh
ouch compress dir/ out.tar.gz     # 圧縮 (拡張子から形式を判断)
ouch c file.txt out.zst           # alias は c
ouch decompress archive.zip       # 展開
ouch d archive.tar.gz -d out/     # 展開先を指定
ouch list archive.zip             # 中身を見る
```

対応形式は tar, zip, gz, 7z, xz, lzma, bz2, bz3, lz4, sz, zst, rar, br。

### tokei (コード行数)

```sh
tokei                    # カレント以下を言語別に集計
tokei src/               # パスを指定
tokei -s lines           # 行数順に並べる
tokei -f                 # ファイル単位の内訳も出す
tokei -e '*.min.js'      # 除外パターン
tokei -o json            # JSON で出力
```

### yazi (ファイラ)

シェルから `y` で起動する。yazi を抜けると、シェルがそのときのディレクトリへ `cd` する。`~/.config/zsh/functions/y` というラッパがそうしているので、`yazi` と直接打った場合は cd しない (このラッパは任意のセットアップに含まれる。[shell.md](shell.md#自作の関数) を参照)。

| キー | 動作 |
| --- | --- |
| `h` `j` `k` `l` | 移動 (左が親、右が開く) |
| `Space` | 選択をトグル |
| `y` / `x` / `p` | コピー / 切り取り / 貼り付け |
| `d` / `D` | 削除 (ゴミ箱へ) / 完全に削除 |
| `a` | 新規作成 (末尾が `/` ならディレクトリ) |
| `r` | リネーム (拡張子の手前にカーソルが入る) |
| `.` | 隠しファイルの表示切り替え (既定で表示にしてある) |
| `/` | 表示中の一覧をインクリメンタル検索 |
| `s` / `S` | `fd` でファイル名検索 / `rg` で内容検索 |
| `Tab` | 選択中のファイルの詳細をポップアップ表示 |
| `q` | 終了 (このパスへ cd する) |
| `Q` | cd せずに終了 |
| `~` または `F1` | ヘルプ (全キーバインドの一覧) |

隠しファイルは `~/.config/yazi/yazi.toml` で最初から表示するようにしてある。`.` で切り替えたぶんはその場限りで、次に起動すると表示に戻る。

### jq (JSON)

JSON を整形して表示したり、必要な値だけを取り出したりする。

```sh
jq . file.json                   # 整形して色付け
jq -r '.name' file.json          # 文字列を裸で取り出す (-r)
jq '.items[] | .id' file.json    # 配列を展開して取り出す
jq '.[] | select(.age > 30)'     # 絞り込み
jq -s '.' a.json b.json          # 複数の入力を配列にまとめる
jq 'keys' file.json              # キーの一覧
gh pr list --json number,title | jq -r '.[] | "\(.number) \(.title)"'
```

### direnv (ディレクトリごとの環境変数)

`.envrc` を置いたディレクトリに入ると、そこに書いた環境変数が読み込まれ、出ると元に戻る。プロジェクトごとに接続先や `PATH` を分けられる。

```sh
cd ~/src/github.com/me/proj
echo 'export DATABASE_URL=postgres://localhost/dev' > .envrc
direnv allow
```

`.envrc` は任意のシェルコードとして実行されるので、許可するまでは読まれない。中身を書き換えると許可が外れ、`direnv allow` を打ち直すまで無効のままになる。他人のリポジトリを clone したときは、中を読んでから許可する。

| コマンド | 動作 |
| --- | --- |
| `direnv allow` | このディレクトリの `.envrc` を許可する |
| `direnv deny` | 許可を取り消す |
| `direnv reload` | 読み込み直す |
| `direnv status` | いま何を読み込んでいるかを見る |

`.envrc` の中では補助関数が使える。

```sh
PATH_add bin          # ./bin を PATH の先頭に足す
dotenv                # .env を読み込む
```

秘密の値を `.envrc` に直接書くと git に入ってしまう。`dotenv` を呼んでおいて、値そのものは git 管理外の `.env` に置くとよい。

uv で作った仮想環境に入るときは、次の 2 行がよい。

```sh
export VIRTUAL_ENV="$PWD/.venv"
PATH_add .venv/bin
```

`source .venv/bin/activate` でも `python` は切り替わるが、`activate` が `PS1` を書き換えるため、ディレクトリに入るたびに `direnv: PS1 cannot be exported` という警告が出る。仮想環境に入っていることは starship が表示するので、`activate` を読む必要はない。

## git 関連

### delta (差分表示)

`core.pager` と `interactive.diffFilter` に設定してあるので、とくに何もしなくても使われる。ただしこの設定は delta が実際に見つかるときだけ書かれるので、apt に `git-delta` が無い Ubuntu 22.04 では 2 回目の `chezmoi apply` から効く ([理由](design.md#古いディストリでも動く形で配る))。`git diff` `git show` `git log -p` `git add -p` の表示が、そのまま delta のものになる。

```sh
git diff                 # delta で表示される
git diff | delta         # 明示的に通すこともできる
```

`navigate = true` を設定してあるので、ページャの中で `n` / `N` によるファイル単位の移動ができる。行番号は常に表示する設定にしてある。

### git の alias

```sh
git st          # status --short --branch
git sw <branch> # switch
git co <ref>    # checkout
git br          # branch
git lg          # グラフ付きのログ (1 行表示)
git last        # 直前のコミットを差分付きで
git unstage <f> # ステージから戻す
```

ほかにも設定してある挙動がいくつかある。

| 設定 | 効果 |
| --- | --- |
| `push.autoSetupRemote` | 新しいブランチで `git push` だけで upstream が張られる (git 2.37 以降。それ以前は最初だけ `git push -u origin HEAD`) |
| `pull.ff = only` | `git pull` が勝手にマージコミットを作らない |
| `fetch.prune` | 消えたリモートブランチの参照を自動で掃除する |
| `rerere.enabled` | 同じコンフリクトの解決を記憶し、次回自動で再適用する |
| `merge.conflictstyle = zdiff3` | コンフリクト表示に共通の祖先も出る (git 2.35 以降。それ以前は `diff3` に落ちる。[理由](design.md#既知の注意点)) |
| `diff.algorithm = histogram` | 差分がより読みやすい単位で出る |

### gh (GitHub CLI)

```sh
gh auth login                    # 初回の認証
gh repo create <name> --private  # リポジトリ作成
gh repo clone <owner>/<repo>
gh pr create                     # PR を作る
gh pr list / gh pr view / gh pr checkout <番号>
gh pr checks                     # CI の状態
gh issue list
gh run watch                     # Actions の実行を追う
```

### ghq (リポジトリ管理)

clone 先を `<root>/<ホスト>/<owner>/<repo>` に統一する。このリポジトリでは `ghq.root = ~/src` に設定してある。

```sh
ghq get github.com/owner/repo    # ~/src/github.com/owner/repo へ clone
ghq get -u <repo>                # 既に有ればそこで pull
ghq get -l <repo>                # clone 後にそのディレクトリへ移動
ghq list                         # 管理下のリポジトリ一覧
ghq list -p                      # 絶対パスで出す
ghq root                         # root を表示
```

fzf と組み合わせると移動が速い。略語 `gcd` に登録してあるので、`gcd` と打って Space を押せば展開される。fzf を `Esc` でキャンセルすると `cd ""` になるが、zsh では何も起きない。

```sh
cd "$(ghq list -p | fzf)"
```

## Python (uv)

pyenv / venv / pip / pipx の役割を uv 1 つで担う。このリポジトリでは Python の環境を uv に一本化している。

プロジェクトを作って進めるときの流れは次のようになる。

```sh
uv init myproject && cd myproject   # pyproject.toml を作る
uv add requests                     # 依存を追加 (仮想環境は自動で作られる)
uv add --dev pytest                 # 開発用の依存
uv remove requests
uv run python main.py               # プロジェクトの環境で実行する
uv run pytest
uv sync                             # ロックファイルどおりに環境を揃える
uv tree                             # 依存関係をツリーで見る
```

Python 本体のバージョン管理も uv が引き受けるので、pyenv は要らない。

```sh
uv python install 3.13       # 処理系を入れる
uv python list               # 入っているものと入手可能なものを見る
uv python pin 3.13           # プロジェクトで使う版を固定する
```

コマンドとして使うツールは `tool` の配下に入れる。pipx にあたる機能である。

```sh
uv tool install ruff         # PATH に ruff が入る
uv tool list
uv tool upgrade --all
uvx ruff check .             # 入れずに 1 回だけ実行する
```

すでにある `requirements.txt` を使いたいときのために、pip 互換のインターフェースもある。

```sh
uv venv                          # .venv を作る
uv pip install -r requirements.txt
```

## Node.js (fnm)

任意のセットアップなので、`chezmoi init` で「Node.js を入れますか」に yes と答えたときだけ入る。バージョンの管理には fnm を使う。既定は LTS の v24 系である。

```sh
node -v                      # 使っている版
npm -v
fnm list                     # 入っている版の一覧
fnm default                  # 既定の版
```

版を足したり切り替えたりする。

```sh
fnm install 22               # 22 系の最新を入れる
fnm install --lts            # LTS の最新を入れる
fnm use 22                   # このシェルだけ切り替える
fnm default 22               # 既定を変える (新しいシェルから効く)
fnm uninstall v22.22.0
```

`fnm use` が効くのはそのシェルの中だけで、別のタブには影響しない。既定そのものを変えるのは `fnm default` のほうである。

プロジェクトごとに版を決めたいときは `.node-version` か `.nvmrc` を置く。そのディレクトリに `cd` すると自動で切り替わる。どちらも無ければ `package.json` の `engines.node` も見る (fnm の `--resolve-engines` が既定で有効なため)。

```sh
node -v > .node-version
```

入っていない版が指定されていると、移動のたびにその旨が出る。指示どおり `fnm install` すれば止まる。

`chezmoi edit-config` で `nodejs` を `false` に戻しても、入れたものは消えない。chezmoi は管理から外れたものを消さないためである。Node の実体は数百 MB あるので、要らなくなったら手で片付ける。

```sh
rm -rf ~/.local/share/fnm                 # fnm が入れた Node 一式
rm -f ~/.local/share/dotfiles/bin/fnm     # fnm 本体 (Linux で externals から来た場合)
```

`npm -g` で入れたものは、版ごとに分かれた場所に入る。`fnm default` で既定の版を変えると付いてこないので、入れ直しが要る。何が入っているかは切り替える前に控えておく。

```sh
npm ls -g --depth=0
```

## Rust (rustup)

任意のセットアップなので、`chezmoi init` で「Rust を入れますか」に yes と答えたときだけ入る。ツールチェインの管理には rustup を使う。既定は stable である。

```sh
cargo --version
rustc --version
rustup show                  # 入っているツールチェインと既定
rustup update                # rustup 自身とツールチェインを更新する
```

ツールチェインやコンポーネントを足す。

```sh
rustup toolchain install nightly
rustup default nightly       # 既定を変える
rustup component add rust-analyzer
rustup target add wasm32-unknown-unknown
```

プロジェクトごとに版を決めたいときは `rust-toolchain.toml` を置く。そのディレクトリの中では `cargo` がそこに書いた版で動く。

```toml
[toolchain]
channel = "1.90"
```

`cargo install` で入れたコマンドは `~/.local/share/cargo/bin` に入り、そのまま PATH が通っている。

```sh
cargo install cargo-edit
cargo install --list         # 入れたものの一覧
```

`chezmoi edit-config` で `rust` を `false` に戻しても、入れたものは消えない。chezmoi は管理から外れたものを消さないためである。ツールチェインは 1 GB 前後あるので、要らなくなったら手で片付ける。

```sh
rm -rf ~/.local/share/rustup ~/.local/share/cargo   # rustup とツールチェイン、cargo install したもの一式
```

`rustup self uninstall` は使わない。`false` で apply したあとのシェルには `RUSTUP_HOME` と `CARGO_HOME` が無いので、rustup は既定の `~/.rustup` と `~/.cargo` を探しにいき、「入っていない」と言って何も消さない。

以前から `~/.rustup` と `~/.cargo` で rustup を使っていたマシンでは、このセットアップが新しい置き場にツールチェインを入れ直す。古いほうはそのまま残るので、`cargo install` で入れていたものを控えてから片付ける。`~/.profile` や `~/.bashrc` に rustup が書き足した `. "$HOME/.cargo/env"` の行も消しておく。

```sh
CARGO_HOME=~/.cargo cargo install --list    # 古い置き場で入れていたもの
rm -rf ~/.rustup ~/.cargo
```

## AI コーディングエージェント

いずれも任意のセットアップで、`chezmoi init` で yes と答えたものだけが入る。認証は入れただけでは済んでいないので、初回に自分で通す。

| コマンド | 認証 | 更新 |
| --- | --- | --- |
| `claude` | 起動するとブラウザが開く | 本体がバックグラウンドで自動更新する |
| `codex` | `codex login` | 本体が自動更新する |
| `copilot` | 起動して `/login` | 自動ではない。`copilot update` を自分で打つ |

3 つとも `~/.local/bin` に入る。`chezmoi apply` が再び入れ直すことはなく、入っていないときだけ導入する。消したいときは各ツールの手順に従う (Claude Code なら `rm -f ~/.local/bin/claude && rm -rf ~/.local/share/claude`)。消したうえで入れ直されたくなければ、`chezmoi edit-config` で該当のキーを `false` にしておく。

なぜパッケージマネージャではなく公式スクリプトで入れているのかは [design.md](design.md#ai-エージェントの入れ方) に書いた。
