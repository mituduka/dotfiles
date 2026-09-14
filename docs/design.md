# 設計と経緯

なぜこの構成にしたのか、どこでつまずいたのかを書き残しておく。ふだん使うぶんには読まなくてよい。何かが思ったとおりに動かないときに開く。

- [ファイルの置き場と PATH の順序](#ファイルの置き場と-path-の順序)
- [chezmoi 自身を PATH に残す](#chezmoi-自身を-path-に残す)
- [パッケージの実在は実行時に問い合わせる](#パッケージの実在は実行時に問い合わせる)
- [Arch の全システム更新](#arch-の全システム更新)
- [~/.zshrc をシンボリックリンクにしている](#zshrc-をシンボリックリンクにしている)
- [履歴と setopt を .zshrc に書く](#履歴と-setopt-を-zshrc-に書く)
- [外部アセットをチェックサムで固定する](#外部アセットをチェックサムで固定する)
- [Ghostty の Option + 矢印](#ghostty-の-option--矢印)
- [tmux の status-interval を 1 にしない](#tmux-の-status-interval-を-1-にしない)
- [re-add と merge が使えない](#re-add-と-merge-が使えない)
- [旧構成からの移行](#旧構成からの移行)
- [既知の注意点](#既知の注意点)

## ファイルの置き場と PATH の順序

このリポジトリが置くバイナリは 2 か所に分かれていて、システムのディレクトリを挟んで PATH の前と後ろに入る。この順序に意味がある。

| ディレクトリ | PATH での位置 | 中身 |
| --- | --- | --- |
| `~/.local/bin` | 前 | 自分のスクリプト、`chezmoi` 本体、Debian 系の改名リンク |
| `/usr/bin` など | 中 | apt / pacman / Homebrew が入れたもの |
| `~/.local/share/dotfiles/bin` | 後 | GitHub Releases から取ったバイナリ (Linux のみ) |

GitHub Releases から取ったバイナリを末尾に置いているのには理由がある。これを先頭に置くと、pacman が入れた新しい `procs` があっても、このリポジトリでバージョンを固定した古い `procs` のほうが先に見つかってしまう。末尾に置けば、パッケージマネージャが入れたものがあればそちらを使い、無いときだけ Releases 版を使うことになる。

この順序にしておけば、`.chezmoiexternal.toml.tmpl` にはディストリごとの収録の差を気にせず全部を書いておける。そのかわり、ほとんどのツールが pacman に揃っている Arch でも一度はダウンロードが走る。置かれるだけで使われないバイナリができるが、そこは割り切った。

Debian 系では `bat` と `fd` が `batcat`、`fdfind` という名前で入る。そのままでは正規の名前で呼べないので、`~/.local/bin` にリンクを張っている。対応表は持たせず、正規名が PATH に無く、別名のほうが存在するときにリンクを張る、という書き方にした。同じような改名が増えても 1 行足すだけで済む。

## chezmoi 自身を PATH に残す

`get.chezmoi.io` は、実行したディレクトリの `bin/` にバイナリを置くだけで終わる。そこは PATH に入り続ける場所ではないので、そのままにしておくと、後日 `chezmoi update` を実行しようとしたときに chezmoi が見つからない。

- macOS — Brewfile の `brew "chezmoi"` が担当する。
- Arch — `extra/chezmoi` を pacman で入れる。
- Ubuntu — 収録が無いので、ブートストラップに使ったバイナリをそのまま `~/.local/bin` へ複製する。

最後のやり方ができるのは、chezmoi がスクリプトに `CHEZMOI_EXECUTABLE` という環境変数で自分の絶対パスを教えてくれるからである。ダウンロードし直さずに済むうえ、ブートストラップに使った版とも確実に一致する。

## パッケージの実在は実行時に問い合わせる

パッケージ名の対応表を引くだけでは足りないので、そのディストリに実在するかどうかを毎回確かめている。

```sh
apt-cache show <pkg>   # Debian 系
pacman -Si <pkg>       # Arch
```

こうしておけば、ディストリやバージョンによる収録の差を、条件分岐を増やさずに扱える。見つからなかったものは、GitHub Releases から取得する経路に回す。そこにも宣言が無ければ、導入できなかったと警告を出す。入ったつもりのまま先へ進まないようにするためである。

## Arch の全システム更新

セットアップの途中で `pacman -Syu` が走る。Arch で `-Sy` だけして個別にパッケージを導入すると部分アップグレードになり、共有ライブラリの不整合を起こす。公式にも非推奨とされているので、`-Syu` で全体を揃えることにした。

そのため、dotfiles を入れるつもりで実行したら数百のパッケージとカーネルまで更新された、ということが起こりうる。更新したくない時期には実行しないほうがいい。

## ~/.zshrc をシンボリックリンクにしている

`ZDOTDIR` を設定しているので、zsh が読むのは `~/.config/zsh/.zshrc` だけで、ホーム直下の `~/.zshrc` は読まれない。ここに何も置かないでおくと、`$HOME/.zshrc` を決め打ちしているインストーラが、誰も読まないファイルを作って終わってしまう。エラーも出ないので、書き足されたことにすら気づけない。

そこで `~/.zshrc` を `~/.config/zsh/.zshrc` へのシンボリックリンクにした (ソースでは `symlink_dot_zshrc`)。こうしておけば、インストーラの追記は実体のファイルに届くし、`chezmoi status` にも現れる。zsh がこのリンクを辿ることはないので、設定を二重に読み込む心配もない。

ただし、`sed -i` を使うインストーラや、いったん退避してから書き戻すインストーラは、リンクを普通のファイルに置き換えてしまうことがある。そのときは `chezmoi status` に `.zshrc` 自体が現れるので、`chezmoi apply` で張り直す。

追記をソースへ取り込む手順は [chezmoi.md](chezmoi.md#インストーラに設定を書き換えられたとき)に書いた。

## 履歴と setopt を .zshrc に書く

macOS の `/etc/zshrc` は `.zshenv` より後、`.zshrc` より前に読まれる。そこで次の 4 つが無条件に上書きされる。

```sh
HISTFILE=${ZDOTDIR:-$HOME}/.zsh_history
HISTSIZE=2000
SAVEHIST=1000
setopt BEEP
```

つまり `.zshenv` に書いても効かない。そこで、`/etc/zshrc` より後に読まれる `.zshrc` で設定し直している。履歴まわりの設定を足すときは、書く場所に気をつける。

`HISTFILE` `HISTSIZE` `SAVEHIST` `LISTMAX` は zsh 自身が読むシェル変数なので、export してはいけない。とくに `HISTFILE` を export すると bash も同じ値を見るようになり、zsh から起動した bash が zsh の履歴ファイルに追記してしまう。`extended_history` の形式のなかに生の行が混ざることになる。

`HISTSIZE` と `SAVEHIST` を同じ値にしてあるのは、zsh がメモリに持っている分しか履歴ファイルへ書かないからである。以前は `HISTSIZE=1000` に対して `SAVEHIST=100000` としていて、実際には 1000 件しか残っていなかった。

## 外部アセットをチェックサムで固定する

`.chezmoiexternal.toml.tmpl` では、GitHub Releases のバイナリとフォントについて、バージョンとチェックサムを固定している。値が合わなければ `chezmoi apply` はその場で止まる。

止まった場所より後ろのものは配置されない。したがって、上流が既存のタグのアセットを差し替えると、新しいマシンでのセットアップが必ず失敗する。厄介なのは、すでに使っているマシンでは `refreshPeriod` のあいだキャッシュが使われるので、この食い違いに気づかないまま動き続けることである。`chezmoi apply --refresh-externals` を実行したとき、あるいは新しいマシンを用意したときになって、はじめて表に出てくる。

そこで `scripts/update-externals.sh` を用意して、固定した内容と上流とを照合できるようにした (手順は [chezmoi.md](chezmoi.md#外部アセットの更新))。照合は x86_64 と aarch64 の両方について行う。片方のアセットだけが差し替えられることがあり、x86_64 しか見ていないと、arm64 のマシンで初めて失敗する。

Claude Code の Skills については、Gist のリビジョン (コミット SHA) まで含めて URL を固定している。内容で指定していることになるので、中身が変わりようがない。`raw/SKILL.md` のままにしておくと、第三者の Gist の最新版が `refreshPeriod` ごとに黙って降ってきて、それを Claude Code が指示として読むことになる。

固定した以上、上流が更新されても自動では追いつかない。そこで `update-externals.sh` は Skills も照合の対象にしてある。リリースと違ってバージョン番号が無いので、Gist の API が返す最新リビジョンと突き合わせる。更新を受け入れるかどうかは人が決めることなので、`--diff` で固定中との差分を読んでから `--write` する、という順序にした。バイナリの更新と違い、ここで受け入れているのは Claude への指示そのものである。

zsh プラグインと TPM は `type = "git-repo"` でブランチを追いかけるので、チェックサムを持たせていない。内容が変わることを前提にした取得方法であり、ハッシュの不一致で失敗することもない。

## Ghostty の Option + 矢印

tmux は `M-Left` と `M-Right` でペインを移動する。ところが macOS では、この 2 つが tmux まで届かないことがある。原因は 2 つある。

1. Option キーを Alt として送る設定がいる。Ghostty には `macos-option-as-alt = true` を設定してある。
2. 端末側の既定のキーバインドが邪魔をする。Ghostty は `alt+arrow_left` と `alt+arrow_right` をシェルの単語移動 (`esc:b` / `esc:f`) に割り当てているので、このままでは tmux まで届かない。上下の矢印には既定の割り当てが無いため、上下だけ動いて左右が動かない、という分かりにくい症状になる。

そこで、ghostty 側で本来の CSI シーケンスを送るように戻してある。

```
keybind = alt+arrow_left=csi:1;3D
keybind = alt+arrow_right=csi:1;3C
```

このままではシェルの単語移動が使えなくなるので、`.zshrc` で割り当て直している。tmux の中では tmux が先に受け取るので、ペインの移動のほうが優先される。

```sh
bindkey '\e[1;3D' backward-word
bindkey '\e[1;3C' forward-word
```

Option をまったく使わずに済ませる手もある。tmux 既定の `prefix + 矢印` はリピートが効くので、prefix を一度押したあとは矢印を連打するだけで移動できる。

## tmux の status-interval を 1 にしない

ステータスバーの更新は 5 秒ごとにしてある。tmux-online-status と tmux-battery は更新のたびに外部コマンドを起動し、前者は ping を送る。ここを 1 秒にすると、毎秒 1 発の ICMP が流れ続けることになる。表示している時刻は分単位なので、5 秒あれば足りる。

## re-add と merge が使えない

ホーム側の変更をソースへ取り込む `chezmoi re-add` は、テンプレートには効かない。`.zshrc` は `dot_zshrc.tmpl` から作られるので、その対象外になる。しかもエラーにはならず、終了コード 0 で返るのに、ソースは何も変わらない。展開後の内容でテンプレートを上書きしてしまわないための仕様で、`--help` にも `chezmoi will not overwrite templates` と書かれている。

`chezmoi merge` による三方向マージも使えない。既定のマージツールが `vimdiff` なのに、vim は Brewfile にも Linux の `PACKAGES` 表にも入れていないからである。テキストエディタは扱わないという方針をそのまま通した結果で、`chezmoi doctor` が次の警告を出すのもこれが理由である。

```
warning   merge-command               vimdiff not found in $PATH
```

同じ出力に出る `edit-command` の警告のほうは無視してよい。`$ZDOTDIR/.zshenv` が `EDITOR` に nano を設定しているので、`chezmoi edit` は nano で開く。

## 旧構成からの移行

chezmoi が新しい設定を配置するだけでは足りず、手で消さなければならないものがある。新しいマシンにはそもそも存在しないので、この節は読み飛ばしてよい。

| 消すもの | 理由 |
| --- | --- |
| `~/.gitconfig` | git は `~/.config/git/config` を読んだ後に `~/.gitconfig` を読む。残しておくと古いほうの設定が優先される |
| `~/.zprofile` | `ZDOTDIR` を設定しているので、zsh が読むのは `$ZDOTDIR/.zprofile` のほう。ホーム直下のものは読まれないまま残る |

`~/.local/bin` に置いていた GitHub Releases 由来のバイナリ (`btm` `ghq` `uv` `uvx` `procs` `ouch` `yazi` `ya`) のほうは、`run_once_after_25-migrate-local-bin.sh` が片付ける。消すのは、新しい置き場に同じ名前の実体があり、かつ自分で張ったシンボリックリンクでないものだけである。

この判定は名前しか見ていないので、同じ名前で自分が入れたものまで消える。たとえば uv の公式インストーラが置いた `~/.local/bin/uv` は消える。コマンド自体は新しい置き場のものが引き継ぐが、版はこのリポジトリで固定しているものに変わる。自分の版を使い続けたいなら、先に PATH の前のほうに来る別の場所へ移しておく。何を消したかは 1 件ずつログに出る。

## 既知の注意点

- 対象は Apple Silicon の macOS だけで、Intel Mac ではパッケージ導入スクリプトが最初に停止する。
- 以前の構成で `/etc/zshenv` に `ZDOTDIR` を書いていたとしても、残したまま動く。どちらの経路をたどっても `$ZDOTDIR/.zshenv` にたどり着くからである。不要なら root 権限で削除してかまわない。
- zsh-abbr v6 が内包する zsh-job-queue は、キューの置き場を `${TMPDIR:-/tmp}/zsh-job-queue` に決め打ちしている。`TMPDIR` がユーザごとに分かれていない Linux ではこれが全ユーザ共有になり、最初に zsh を起動した人が作ったディレクトリに 2 人目が書き込めず、略語がひとつも展開されなくなる。`.zshrc` で `JOB_QUEUE_TMPDIR` を指定して、ユーザごとに分けてある。
