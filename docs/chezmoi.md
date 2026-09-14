# 設定を変える・配る

設定を足したり書き換えたり、別のマシンへ配ったりするときの手順をまとめる。chezmoi そのものの詳しい説明は[公式ドキュメント](https://www.chezmoi.io/)にある。

- [基本のサイクル](#基本のサイクル)
- [ファイル名の規則](#ファイル名の規則)
- [設定ファイルを管理下に入れる](#設定ファイルを管理下に入れる)
- [OS ごとに内容を変える](#os-ごとに内容を変える)
- [ツールを追加する](#ツールを追加する)
- [スクリプト](#スクリプト)
- [外部アセットの更新](#外部アセットの更新)
- [インストーラに設定を書き換えられたとき](#インストーラに設定を書き換えられたとき)
- [他のマシンへ配る](#他のマシンへ配る)
- [困ったとき](#困ったとき)

## 基本のサイクル

ソースは `~/.local/share/chezmoi` にある。ここを編集して、ホームへ反映する。

```sh
chezmoi edit ~/.zshrc     # ソース側のファイルを開く
chezmoi diff              # 反映したら何が変わるかを見る
chezmoi apply             # 反映する
```

ホーム直下の実ファイルを直接編集しても、次に `apply` したときに上書きされてしまう。うっかり直接編集してしまったときは、その内容をソースへ取り込める。

```sh
chezmoi status            # 変更があるファイルを一覧する (git status に相当)
chezmoi re-add            # 直接編集した内容をソースへ取り込む
```

ただし `re-add` はテンプレート (`.tmpl`) には効かない。`.zshrc` のようなテンプレート由来のファイルは、自分で書き写すことになる ([design.md](design.md#re-add-と-merge-が使えない))。

## ファイル名の規則

chezmoi はソースのファイル名を変換してホームに置く。

| ソース | 配置先 |
| --- | --- |
| `dot_zshenv` | `~/.zshenv` |
| `dot_config/tmux/tmux.conf` | `~/.config/tmux/tmux.conf` |
| `dot_config/zsh/dot_zshrc.tmpl` | `~/.config/zsh/.zshrc` |
| `dot_local/bin/executable_foo.sh` | `~/.local/bin/foo.sh` (実行ビット付き) |
| `private_dot_ssh/config` | `~/.ssh/config` (`~/.ssh` が 0700) |
| `symlink_dot_zshrc` | `~/.zshrc` (シンボリックリンク。ファイルの中身がリンク先) |

| 接頭辞・接尾辞 | 意味 |
| --- | --- |
| `dot_` | `.` に置き換わる |
| `executable_` | 実行ビットを立てる |
| `private_` | 他人から読めないパーミッションにする (ファイルなら 0600、ディレクトリなら 0700) |
| `symlink_` | シンボリックリンクとして配置する |
| `.tmpl` | Go テンプレートとして評価してから配置する |

ソースには置くけれどもホームへは配置したくないものは、`.chezmoiignore` に書いておく。`README.md` や `docs/` はこうして除外している。

## 設定ファイルを管理下に入れる

すでにホームにあるファイルを取り込んだり、管理から外したりする。

```sh
chezmoi add ~/.config/foo/config              # そのまま取り込む
chezmoi add --template ~/.config/foo/config   # テンプレートとして取り込む

chezmoi forget ~/.config/foo/config   # 管理をやめる (ホームのファイルは残る)
chezmoi destroy ~/.config/foo/config  # ホームからも消す

chezmoi managed            # 管理下のパス一覧
chezmoi unmanaged          # ホームにあって管理外のもの
```

## OS ごとに内容を変える

`.tmpl` を付けたファイルでは Go テンプレートが使える。

```gotmpl
{{ if eq .chezmoi.os "darwin" -}}
eval "$(/opt/homebrew/bin/brew shellenv)"
{{ end -}}
```

よく使う変数を挙げる。

| 変数 | 値 |
| --- | --- |
| `.chezmoi.os` | `darwin` / `linux` |
| `.chezmoi.arch` | `amd64` / `arm64` |
| `.chezmoi.hostname` | ホスト名 |
| `.chezmoi.homeDir` | ホームディレクトリの絶対パス |
| `.headless` | 初回プロンプトで決めたヘッドレス判定 |
| `.name` / `.email` | 初回プロンプトで入力した git の設定 |

後ろの 3 つは `.chezmoi.toml.tmpl` が作り、`~/.config/chezmoi/chezmoi.toml` に保存されている。値を変えるときは `chezmoi edit-config` で書き換えてから `chezmoi apply` する。

書いたテンプレートは、ホームへ反映しなくても展開結果を確認できる。

```sh
chezmoi execute-template < dot_config/zsh/dot_zshrc.tmpl | head -40
chezmoi cat ~/.config/zsh/.zshrc     # 展開結果をそのまま見る
```

## ツールを追加する

入手経路が 2 つあるので、ツールによって使い分ける。

### パッケージマネージャで入るもの

`.chezmoiscripts/run_once_before_10-install-packages.sh.tmpl` を編集する。

macOS はヒアドキュメントの Brewfile に 1 行足す。

```
brew "ripgrep-all"
```

Linux は `PACKAGES` の表に `ツール名:debian でのパッケージ名:arch でのパッケージ名` の形式で足す。そのディストリに収録が無ければ `-` を書いておく。

```
ripgrep-all:ripgrep-all:ripgrep-all
```

パッケージが実在するかどうかは実行時に問い合わせるので、ディストリのバージョンによる収録の差は気にせず書いてよい。見つからなければ、次の externals が引き受ける。

### パッケージマネージャに無いもの

`.chezmoiexternal.toml.tmpl` に宣言する。GitHub Releases から取得する場合はこう書く。

```toml
[".local/share/dotfiles/bin/foo"]
    type = "archive-file"
    url = "https://github.com/owner/foo/releases/download/v1.2.3/foo-{{ $rustArch }}-unknown-linux-gnu.tar.gz"
    path = "foo-{{ $rustArch }}-unknown-linux-gnu/foo"
    executable = true
    refreshPeriod = "720h"
    [".local/share/dotfiles/bin/foo".checksum]
        sha256 = "..."
```

置き場は `~/.local/bin` ではなく `~/.local/share/dotfiles/bin` にする。この 2 つは PATH の中での位置が違うので、apt や pacman が同じツールを入れているときにどちらが使われるかが変わってしまう ([design.md](design.md#ファイルの置き場と-path-の順序))。

`path` にはアーカイブの中でのパスを書く。実物の中身を確認してから書いたほうがいい。

```sh
curl -fsSL <url> -o /tmp/x.tar.gz && tar -tzf /tmp/x.tar.gz
```

チェックサムは、ダウンロードしたファイルの検証に使う。バージョンを上げたら必ず取り直す。x86_64 と aarch64 でアセットが分かれているなら、両方の値が要る。

```sh
curl -fsSL <url> | shasum -a 256
```

`type` は用途で使い分ける。

| type | 用途 |
| --- | --- |
| `git-repo` | リポジトリをそのまま置く (zsh プラグイン、TPM) |
| `archive` | アーカイブを展開して 1 ディレクトリにする (フォント) |
| `archive-file` | アーカイブから 1 ファイルだけ取り出す (バイナリ) |
| `file` | 単一ファイルをダウンロードする (Claude Skills) |

## スクリプト

`.chezmoiscripts/` に置く。接頭辞で実行タイミングと頻度が決まる。

| 接頭辞 | いつ走るか |
| --- | --- |
| `run_once_before_` | 1 回だけ。設定ファイルの配置より前 |
| `run_once_after_` | 1 回だけ。設定ファイルの配置より後 |
| `run_onchange_after_` | 内容が変わったとき。配置より後 |

数字は実行順を決めるための命名規則で、chezmoi の機能ではない。

テンプレートが空文字列に展開されたスクリプトは実行されない。特定の OS でだけ走らせたいときは、この性質を使ってスクリプト全体を `{{ if ... }}` で包む。`40-font-cache` と `25-migrate-local-bin` がその書き方をしている。

`run_once_` が「実行済みかどうか」を判断する材料は、テンプレートを展開したあとの内容のハッシュである。中身が変われば、もう一度実行される。逆に、内容を変えないまま実行させたいときは、記録のほうを消す。

```sh
chezmoi state delete-bucket --bucket=scriptState
chezmoi apply
```

`run_onchange_` を別のファイルの変更に反応させたいときは、そのファイルのハッシュをコメントに埋め込んでおく。tmux のプラグイン導入スクリプトがこの書き方をしている。

```gotmpl
# tmux.conf hash: {{ include "dot_config/tmux/tmux.conf" | sha256sum }}
```

## 外部アセットの更新

`.chezmoiexternal.toml.tmpl` で固定しているバージョンとチェックサムを、上流の最新に合わせるためのスクリプトを用意してある。これは自動では走らない。

```sh
scripts/update-externals.sh
```

そのまま実行すると確認するだけで、ファイルは書き換えない。GitHub Releases のバイナリとフォントを上の表に、Gist から取っている Claude Code の Skills を下の表に出す。

```
tool      current      latest       state
--------------------------------------------------------------
bottom    0.14.9       0.14.9       最新 / ハッシュ一致
ouch      0.8.0        0.8.2        更新あり
uv        0.12.13      0.12.13      ハッシュ不一致 (上流が差し替えた)

skill                      current   latest    state
--------------------------------------------------------------
japanese-tech-writing      c7189cdc  8f2d5761  更新あり
cognitive-rhythm-writing   a3b1e26b  a3b1e26b  最新 / ハッシュ一致
```

| 表示 | 意味 | すること |
| --- | --- | --- |
| 最新 / ハッシュ一致 | 固定内容が上流と一致している | なし |
| 更新あり | 新しいリリース、または新しい Gist のリビジョンが出ている | 更新したければ `--write` |
| ハッシュ不一致 | 上流が既存タグのアセットを差し替えた | `--write` で取り直す |
| 問い合わせに失敗 | GitHub API を呼べなかった。未認証だと 1 時間に 60 回までなので、そこに達したのかもしれない | `gh auth login` で認証してからやり直す |

3 つ目をそのままにしておくと、新しいマシンでのセットアップが必ず失敗する ([design.md](design.md#外部アセットをチェックサムで固定する))。

Skill の中身は Claude Code が指示として読むテキストなので、書き換える前に何が変わったのかを読む。`--diff` は固定中のリビジョンと最新の差分を出す。

```sh
scripts/update-externals.sh --diff
```

中身を見て、更新すると決めてから書き換える。

```sh
scripts/update-externals.sh --write
git diff .chezmoiexternal.toml.tmpl
chezmoi apply --refresh-externals
```

Skill は URL に埋めたリビジョンと `sha256` の両方が書き換わる。Skill を足したときにスクリプト側へ登録する必要は無い。対象は `.chezmoiexternal.toml.tmpl` の `.claude/skills/` 以下の宣言から拾っている。

新しいリビジョンでファイル名まで変わっていると、URL が 404 になって取得できない。その場合は書き換えを中止して URL を表示するので、手で直す。

パッケージマネージャの管理対象バイナリはここでのアップデート対象外。

## インストーラに設定を書き換えられたとき

ツールのインストーラが `.zshrc` の末尾に初期化コードを書き足すことがある。chezmoi の管理下にあるファイルなので、そのままにしておくと次の `chezmoi apply` で消えてしまう。

もっとも、黙って消されることはない。chezmoi は最後に自分が書き込んだ内容のハッシュを覚えていて、それとずれていれば必ず確認してくる。

```
$ chezmoi apply
.zshrc has changed since chezmoi last wrote it (diff/overwrite/all-overwrite/skip/quit)?
```

ここで `overwrite` を選ぶと追記が消えてしまう。`skip` か `quit` で抜けてから、次の手順でソースに取り込む。

1. 何が足されたかを見る。差分は「ソース → ホーム」の向きなので、追記された行は `-` で表示される。

   ```sh
   chezmoi diff ~/.config/zsh/.zshrc
   ```

2. ソース側に書き直す。インストーラが出力した行をそのまま貼り付けず、存在チェックで包む。この設定は 3 つの OS で共有しているので、ツールが入っていないマシンで裸の `eval` を実行すると、シェルの起動そのものが壊れてしまう。

   ```sh
   chezmoi edit ~/.config/zsh/.zshrc
   ```

   ```sh
   if command -v sometool >/dev/null 2>&1; then
     eval "$(sometool init zsh)"
   fi
   ```

   書く位置は、既に `zoxide` / `fzf` / `starship` が並んでいるあたりに揃える。プラグイン節の順序は動かさない。

3. 反映して読み直す。

   ```sh
   chezmoi apply && exec zsh
   ```

4. ツール本体の導入経路も登録しておく。これを忘れると、他のマシンではコマンドが入らないままになる ([ツールを追加する](#ツールを追加する))。

追記が長いときは、`chezmoi diff` の差分だけでは前後の文脈が分かりにくい。ホーム側のファイルを開いて、そちらを見ながら書き写す。

```sh
bat ~/.config/zsh/.zshrc
```

## 他のマシンへ配る

ソースは普通の git リポジトリなので、いつもどおり commit して push する。

```sh
chezmoi cd
git add -A && git commit -m "..." && git push
exit
```

受け取る側は 1 コマンドで済む。git pull から外部リソースの再取得までをまとめて行う。

```sh
chezmoi update
```

外部リソースのうち再取得されるのは、`refreshPeriod` を過ぎたものだけである。強制的に取り直したいときは `chezmoi apply --refresh-externals` を使う。

## 困ったとき

まず `chezmoi doctor` を走らせると、足りないコマンドや設定の問題を指摘してくれる。`merge-command` と `edit-command` の警告は想定どおりなので、無視してよい。

| 症状 | 対処 |
| --- | --- |
| ソースの場所が分からない | `chezmoi source-path` |
| 展開後の内容を見たい | `chezmoi cat <ターゲットのパス>` |
| 適用せずに動作を見たい | `chezmoi apply -n -v` |
| `run_once_` を再実行したい | `chezmoi state delete-bucket --bucket=scriptState` |
| 外部リソースを取り直したい | `chezmoi apply --refresh-externals` |
| `SHA256 mismatch` で apply が止まる | `scripts/update-externals.sh` で確認し `--write` で取り直す |
| フォントが入っていない | 上と同じ。その後 Linux では `fc-cache -f` |
| プロンプトの答えを変えたい | `chezmoi edit-config` して `chezmoi apply` |
| 状態を全部忘れさせたい | `chezmoi state reset` (次回すべて再実行される) |
