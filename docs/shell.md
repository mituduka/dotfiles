# シェルの使い方

zsh 本体とプラグインの使い方をまとめる。個々のコマンドについては [commands.md](commands.md) を見てほしい。

- [略語 (zsh-abbr)](#略語-zsh-abbr)
- [入力補助](#入力補助)
- [ディレクトリ移動 (zoxide)](#ディレクトリ移動-zoxide)
- [絞り込み (fzf)](#絞り込み-fzf)
- [履歴](#履歴)
- [設定ファイルの構成](#設定ファイルの構成)
- [自作の関数](#自作の関数)

## 略語 (zsh-abbr)

alias と違って、入力した時点で実際のコマンドに展開される。`ll` と打って Space か Enter を押すと、その場で `ls -l` に変わる。履歴にも展開後が残るので、後から `history` を見たときに何を実行したのかが分かる。

| 略語 | 展開後 |
| --- | --- |
| `ll` | `ls -l` |
| `la` | `ls -l -A` |
| `lt` | `ls --tree` |
| `l` | `clear && ls` |
| `gcd` | `cd "$(ghq list -p \| fzf)"` |

`gcd` は ghq で管理しているリポジトリを fzf で選んで移動する。

```sh
abbr list            # 一覧
abbr expand ll       # 展開結果を確認するだけ
```

### 略語を追加する

`abbr add` で直接足してはいけない。書き込み先の `~/.config/zsh-abbr/user-abbreviations` は chezmoi が管理しているので、次に `chezmoi apply` したときに消えてしまう。ソース側を編集する。

```sh
chezmoi edit ~/.config/zsh-abbr/user-abbreviations
chezmoi apply
exec zsh
```

その場で試したいときは `abbr add` を使ってもよい。ただし、消えてしまう前にソースへ取り込んでおく。

```sh
abbr add gs="git status"
chezmoi add ~/.config/zsh-abbr/user-abbreviations
```

## 入力補助

### zsh-autosuggestions

履歴から続きを薄いグレーで提案する。

| キー | 動作 |
| --- | --- |
| `→` または `Ctrl-E` | 提案を全部受け入れる |
| `Alt-F` | 提案を 1 単語だけ受け入れる |

### zsh-syntax-highlighting

入力中のコマンドを色分けする。緑なら実在するコマンドで、赤なら存在しない。Enter を押す前に打ち間違いに気づけるし、引用符の閉じ忘れも色で分かる。

### 補完

`Tab` で補完し、もう一度 `Tab` を押すと、候補の中をカーソルキーで選べる (`menu select`)。候補は詰めて表示し、50 件を超えるときだけ表示するかどうかを聞く。

補完のキャッシュは `~/.cache/zsh/zcompdump` に置いている。起動を速くするためにキャッシュの鮮度チェックを省いているので、新しく入れたコマンドの補完は、キャッシュを消すまで出てこない。

```sh
rm ~/.cache/zsh/zcompdump && exec zsh
```

## ディレクトリ移動 (zoxide)

一度でも `cd` した場所を覚えていて、使った回数と最後に使った時刻から行き先を推測する。

```sh
z dotfiles       # 部分一致で最も「よく使う」ディレクトリへ飛ぶ
z src github     # 複数の語で絞り込む
z -              # 直前のディレクトリへ戻る
zi               # 候補を fzf で選ぶ
```

覚えた内容が邪魔になったら、一覧を見て消す。

```sh
zoxide query -l              # 記憶しているパスの一覧
zoxide remove /path/to/dir   # 特定のパスを忘れさせる
```

`cd` もこれまでどおり使える。zoxide は `cd` を置き換えるものではない。

## 絞り込み (fzf)

### シェルのキーバインド

| キー | 動作 |
| --- | --- |
| `Ctrl-R` | 履歴を絞り込んで実行 |
| `Ctrl-T` | カレント以下のファイルを選んでコマンドラインに挿入 |
| `Alt-C` | カレント以下のディレクトリを選んで `cd` |

ファイルを探すときは `fd` を使うように設定してあるので、`.gitignore` に書いたものは候補に出てこない。隠しファイルのほうは候補に含まれる。

macOS で `Alt-C` が効かないときは、ターミナルの Option キーの設定を確認する。Ghostty には `macos-option-as-alt = true` を設定してある。

### 絞り込み画面の中での操作

| キー | 動作 |
| --- | --- |
| `Ctrl-J` / `Ctrl-K` | 候補を上下に移動 |
| `Enter` | 決定 |
| `Tab` | 複数選択 (対応しているコマンドのみ) |
| `Esc` / `Ctrl-C` | 中止 |

### 補完トリガー

`**` と打ってから `Tab` を押すと、fzf が起動する。

```sh
vim **<Tab>          # ファイルを選ぶ
cd **<Tab>           # ディレクトリを選ぶ
kill -9 **<Tab>      # プロセスを選ぶ
ssh **<Tab>          # 既知のホストから選ぶ
```

## 履歴

旧構成から移る場合、`~/.config/zsh/.zsh_history` があれば `~/.local/state/zsh/history` へ複製される (移送先がまだ無いときだけ)。元のファイルは残るので、確認したうえで消す。

| 項目 | 値 |
| --- | --- |
| 保存先 | `~/.local/state/zsh/history` |
| メモリ上 (`HISTSIZE`) | 100000 |
| ファイル (`SAVEHIST`) | 100000 |

設定してある挙動のうち、知っておくと役に立つものを挙げる。

| 挙動 | 意味 |
| --- | --- |
| `share_history` | 複数のターミナル間で履歴が即座に共有される |
| `hist_ignore_space` | 行頭にスペースを入れて実行すると履歴に残らない |
| `hist_ignore_all_dups` | 同じコマンドは最新の 1 件だけ残る |
| `hist_verify` | `!!` などの履歴展開は、実行前に一度編集できる |
| `hist_reduce_blanks` | 余分な空白を詰めて記録する |

秘密を含むコマンドを打つときは、行頭にスペースを入れる。

```sh
 export API_KEY=xxxxx      # 行頭のスペースにより履歴に残らない
```

`HISTSIZE` と `SAVEHIST` を同じ値にしてあるのには理由がある ([design.md](design.md#履歴と-setopt-を-zshrc-に書く))。

## 設定ファイルの構成

設定は `~/.config/zsh` にまとめてある。ホーム直下の `~/.zshenv` は `ZDOTDIR` を指すだけの入口で、中身はほとんどない。

```
~/.zshenv           ZDOTDIR を ~/.config/zsh に設定し、その .zshenv を読む
  └ $ZDOTDIR/.zshenv    環境変数だけ (XDG, PATH, LANG, EDITOR, FNM_DIR)
     ↓
  (ログインシェルのみ) /etc/zprofile → $ZDOTDIR/.zprofile
                          macOS ではここで PATH が組み直されるので並べ直す
     ↓
  (macOS のみ) /etc/zshrc が割り込む
     ↓
  $ZDOTDIR/.zshrc       履歴設定・補完・プラグイン・各種初期化
     └ $ZDOTDIR/functions/   自作の関数。1 ファイル 1 関数で autoload する
```

ホーム直下の `~/.zshrc` は読まれない。それでも `~/.config/zsh/.zshrc` へのシンボリックリンクを置いてあるのは、インストーラが書き込んだ内容を実体のファイルに届かせるためである ([design.md](design.md#zshrc-をシンボリックリンクにしている))。

`.zshrc` を書き換えるときは、次の 3 つに気をつける。理由はいずれも `.zshrc` のコメントと [design.md](design.md) に書いてある。

- 節の並び順を変えない。`fpath` への追加は `compinit` より前に、zsh-abbr は `compinit` より後に置く。zsh-syntax-highlighting は必ず最後に読む。
- 履歴と `setopt` は `.zshenv` ではなく `.zshrc` に書く。macOS では `/etc/zshrc` が上書きしてくるからである。
- 外部コマンドを呼ぶ行は `command -v` で包む。この設定は 3 つの OS で共有しているので、ツールが入っていないマシンで裸の `eval` を実行すると、シェルの起動そのものが壊れる。

`PATH` は `.zshenv` で層に分けて組んである。この順序にも意味があるので、[design.md](design.md#ファイルの置き場と-path-の順序) を参照してほしい。

## 自作の関数

自分で書いた zsh 関数は `~/.config/zsh/functions/` に置く。1 ファイルにつき 1 関数で、ファイル名がそのまま関数名になる。`.zshrc` が起動時に読むのはファイル名の一覧だけで、中身は実際に呼ばれたときに読まれる。

いま入っているのは yazi 用の `y` だけである。

関数を足すときは、ファイル名を関数名にして置く。

```sh
chezmoi cd
$EDITOR dot_config/zsh/functions/mkcd
chezmoi apply && exec zsh
```

中身は関数の「本体」だけを書く。`mkcd() { ... }` のようには包まない。`autoload -Uz` はファイルの内容をそのまま本体として扱うので、包むと「関数を定義するだけの関数」になり、1 回目の呼び出しで何も起きなくなる。

```zsh
# mkcd - ディレクトリを作ってそこへ移動する
mkdir -p -- "$1" && builtin cd -- "$1"
```

`.zshrc` に直接書くのと比べて、次の 3 点が違う。

- 起動が速い。呼ばれるまで中身を読まないので、関数が増えても起動時間は変わらない。
- 書き間違えてもシェルの起動は止まらない。`.zshrc` の構文エラーは起動そのものを壊すが、autoload した関数の誤りは、その関数を呼んだときにしか出ない。
- `.zshrc` の節の順序を気にしなくてよい。読み込み順序に意味があるのは `.zshrc` の中だけである。

`chezmoi init` で「自作の zsh 関数を入れますか」に no と答えている場合、このディレクトリは配置されず、`y` も使えない。`chezmoi edit-config` で `zshFunctions` を `true` にすれば入る。

逆に `true` から `false` へ戻したときは、`.zshrc` の autoload だけが消えて `~/.config/zsh/functions/` のファイルは残る。chezmoi は管理から外れたものを消さないためである。気になるならディレクトリごと手で消す。
