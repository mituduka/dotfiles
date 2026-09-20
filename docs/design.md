# 設計と経緯

なぜこの構成にしたのか、どこでつまずいたのかを書き残しておく。ふだん使うぶんには読まなくてよい。何かが思ったとおりに動かないときに開く。

- [ファイルの置き場と PATH の順序](#ファイルの置き場と-path-の順序)
- [chezmoi 自身を PATH に残す](#chezmoi-自身を-path-に残す)
- [パッケージの実在は実行時に問い合わせる](#パッケージの実在は実行時に問い合わせる)
- [Arch の全システム更新](#arch-の全システム更新)
- [~/.zshrc をシンボリックリンクにしている](#zshrc-をシンボリックリンクにしている)
- [履歴と setopt を .zshrc に書く](#履歴と-setopt-を-zshrc-に書く)
- [外部アセットをチェックサムで固定する](#外部アセットをチェックサムで固定する)
- [apply はパス順に進み、途中で止まる](#apply-はパス順に進み途中で止まる)
- [古いディストリでも動く形で配る](#古いディストリでも動く形で配る)
- [AI エージェントの入れ方](#ai-エージェントの入れ方)
- [Node.js を fnm で入れる](#nodejs-を-fnm-で入れる)
- [Ghostty の Option + 矢印](#ghostty-の-option--矢印)
- [tmux の status-interval を 1 にしない](#tmux-の-status-interval-を-1-にしない)
- [re-add と merge が使えない](#re-add-と-merge-が使えない)
- [旧構成からの移行](#旧構成からの移行)
- [既知の注意点](#既知の注意点)

## ファイルの置き場と PATH の順序

このリポジトリが置くバイナリは複数の場所に分かれていて、システムのディレクトリを挟んで PATH の前と後ろに入る。この順序に意味がある。

| ディレクトリ | PATH での位置 | 中身 |
| --- | --- | --- |
| `~/.local/bin` | 前 | 自分のスクリプト、`chezmoi` 本体、AI エージェント、Debian 系の改名リンク |
| `$FNM_DIR/aliases/default/bin` | 前寄り | fnm の既定版の `node` / `npm` (入れた場合のみ) |
| `/usr/bin` など | 中 | apt / pacman / Homebrew が入れたもの |
| `~/.local/share/dotfiles/bin` | 後 | GitHub Releases から取ったバイナリ (Linux のみ) |

fnm の `node` だけは「Releases 由来のものは末尾」という下の原則から外れて、システムのディレクトリより前に置いている。Homebrew や apt の `node` がいても、バージョンを管理しているほうを使いたいからである。fnm 本体のバイナリは原則どおり末尾の `dotfiles/bin` にある。

`~/.local/bin` のほうがさらに前にあるので、そこに `node` を置くと fnm 版より先に見つかる。Node の公式インストーラや `n` を併用しているとこれが起きるため、Node を入れた回にその旨を知らせるようにしてある。

### この順序は 2 回壊されるので、2 回組み直す

PATH を組み立てているのは `$ZDOTDIR/.zshenv` だが、そこで決めた順序はそのまま残らない。後から 2 つのものが割り込んでくる。

1 つは macOS の `/etc/zprofile` で、`path_helper` を呼んで PATH を組み直す。これは `/etc/paths` と `/etc/paths.d` を並べたうえで、既にあったエントリをその後ろへ回す。つまり `~/.local/bin` がシステムのディレクトリより後ろに落ちる。ログインシェルでだけ起きるので、ターミナルを開いて日常的に使う側だけが意図と違う順序になる、という気づきにくい形で出る (Linux の `/etc/zsh/zprofile` はコメントだけで PATH を触らないので、これは macOS に固有の問題である)。

もう 1 つは `.zshrc` の `brew shellenv` で、`/opt/homebrew/bin` を先頭に差し込む。こちらは対話シェルで起きる。

そこで PATH の組み立てを `.zshenv` の中で `_dotfiles_set_path` という関数にまとめ、`$ZDOTDIR/.zprofile` (path_helper の後) と `.zshrc` の `brew shellenv` の直後で呼び直している。`typeset -U` が重複を落とすので、何度呼んでも並びは同じところに落ち着く。この 2 回の呼び直しが無いと、上の表は非対話シェルでしか成り立たない。

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

ここが、このリポジトリで最後に残っている固定できていない部分である。zsh-syntax-highlighting、zsh-autosuggestions、zsh-abbr、TPM の 4 つは、`refreshPeriod` ごとに上流の最新が `--ff-only` で降りてきて、次に開いた対話シェルで無条件に実行される。3 つの独立したアカウントのどれかが乗っ取られれば、`chezmoi apply` を明示的に実行しなくても入ってくる。TPM が入れる 5 つの tmux プラグインも同じで、そちらはさらに TPM 任せなのでバージョンの指定すらない。

タグに固定すれば塞げるが、そうすると 9 つのプラグインを手で追うことになり、`update-externals.sh` が扱えるのはバージョン番号を持つ Releases だけなので自動化もできない。追わなくなったものは結局古いまま放置される。固定して腐らせるより、上流を追い続けるほうが総体としては安全だと判断した。GitHub Releases のバイナリと違って、こちらは中身が読めるテキストであり、必要なら `~/.local/share/zsh/plugins` で `git log` を見られることも理由のひとつである。

## apply はパス順に進み、途中で止まる

`chezmoi apply` はターゲットのパス順に 1 つずつ適用し、途中で失敗するとそこで打ち切る。後ろのものは置かれない。

これが効いてくるのは、`~/.zshenv` が名前の順でほぼ最後に来るからである。`.claude`、`.config`、`.local` はいずれもその手前にあり、externals が置かれるのもそこである。したがって、GitHub Releases のダウンロードが 1 つ落ちただけでも、`~/.zshenv` が置かれないまま apply が終わる。`ZDOTDIR` が決まらないので `~/.config/zsh/.zshrc` (こちらは先に置かれている) が読まれず、「CLI ツールは入ったのにシェルの設定が一切効かない」という形で出る。

失敗そのものは黙って起きるわけではなく、エラーは出るし終了コードも非ゼロになる。それでも「何が置かれなかったか」までは分からないので、失敗したら必ずもう一度 apply する。

第三者の Gist から取る Claude Code の Skills も、パス順では `.claude/skills/...` とほぼ先頭に来る。Gist が消されれば、それだけで全マシンの apply が `~/.zshenv` の手前で止まることになる。これは受け入れている。Skills を `claudeCode` の答えで囲えば影響するマシンは減るが、`~/.claude/skills` はデスクトップアプリや IDE 拡張も読むので、CLI を入れないマシンでも要ることがある。そちらの利便を優先した。

## 古いディストリでも動く形で配る

Ubuntu 22.04 の apt には `delta` `dust` `eza` `sd` `starship` `tokei` が無い。収録の差はディストリのバージョンでも開くので、`.chezmoiexternal.toml.tmpl` はこの 6 つも GitHub Releases から取る対象にしてある。置き場が PATH の末尾なので、収録のある環境では apt / pacman 側が先に見つかり、ここに並べておいて損をすることはない。

配布形式は gnu 版を既定にして、musl 版にするのは 2 つの場合だけである。要求する glibc が 22.04 に収まらないときと、上流が aarch64 向けに musl 版しか配っていないときである。glibc 版は、ビルドに使った環境の glibc より古いシステムでは動かない。glibc は古いバイナリを新しいシステムで動かす方向にしか互換性がないためである。実際 yazi v26.9.1 の `-unknown-linux-gnu` 版は `GLIBC_2.39` を要求し、glibc 2.35 の Ubuntu 22.04 では `version 'GLIBC_2.39' not found` で起動しない。musl 版は静的にリンクされているので、この下限を持たない。

musl 版を既定にしないのは、musl の malloc 実装 (mallocng) が遅いからである。`dust` は並列に走査してノードを大量に確保するので差が大きく、80,000 ファイルの走査で musl 版が 116.5ms、gnu 版が 22.4ms だった。ただし差が出るのは確保の多い処理に限られる。`sd` による 30 万行の置換では 1.14 倍にとどまり、`starship` のプロンプト 1 回では musl 版のほうが速かった。

いま musl 版を使っているのは `sd` `starship` `yazi` の 3 つで、前者が `yazi`、後者が `sd` と `starship` にあたる。`sd` と `starship` は x86_64 だけ gnu 版に分けることもできるが、実測した差がこのとおりなので揃えてある。

固定しているアセットの要求を実際に測ると、`eza` と `tokei` が `GLIBC_2.18`、`uv` が `GLIBC_2.17`、`bottom` `delta` `dust` `ouch` が `GLIBC_2.34` だった。いずれも 22.04 の 2.35 に収まる。

`tokei` はさらに事情が違う。v13 以降のリリースにはバイナリが添付されておらず、実体があるのは 2021 年の v12.1.2 が最後である。そのため `scripts/update-externals.sh` の照合対象からは外してある。載せると毎回「更新あり」と出たうえで、アセットが無いので書き換えにも失敗し続ける。収録のあるディストリでは、そちらの新しい `tokei` が PATH の先に来る。

apt に `git-delta` が無い環境では、`~/.config/git/config` に pager の設定が入るのが 2 回目の `chezmoi apply` になる。chezmoi は対象のパス順に適用するので、`.config/git/config` を書き終えたあとで `.local/share/dotfiles/bin/delta` が置かれるからである。初回に黙って落ちないよう、パッケージ導入スクリプトがそのことを表示する。

## AI エージェントの入れ方

Claude Code、Codex CLI、GitHub Copilot CLI の 3 つは、どれも提供元の公式インストールスクリプトで入れている。3 つとも npm パッケージと Homebrew の cask があり、Claude Code には署名付きの apt / dnf / apk リポジトリまであるので、このリポジトリのふだんの方針 (パッケージマネージャを優先し、無いものだけ GitHub Releases で補う) からは外れる。外した理由は 4 つある。

第一に、3 OS で手順が同一になる。cask は macOS だけで、apt にも pacman にも Codex と Copilot の収録は無い。Claude Code の apt リポジトリを使う道はあるが、鍵の登録と `sudo` が要るうえ、Arch では結局その手が使えない。公式スクリプトなら 3 OS で同じ 1 行になる。`.zshrc` の `source` 先を 3 OS で揃えているのと同じ理由である。

第二に、`sudo` が要らない。3 つとも `~/.local/bin` に入る。ここは既に PATH の先頭にあるので、置き場のために何かを足す必要もない。

第三に、更新の経路が本体側に閉じる。Claude Code はバックグラウンドで自分を更新し、Codex も同じ仕組みを持っている。Copilot だけは自動ではなく `copilot update` を打つ形だが、これも本体の機能である。一方 Homebrew 版は自動更新しないと公式が明記していて、`claude-code` cask に至っては stable チャンネルを追うため約 1 週間遅れる。しかも `brew bundle` は既にある formula を upgrade しないので、`chezmoi apply` を繰り返しても上がらない。自分で `brew upgrade` を打つまで古いままになる (Claude Code には `CLAUDE_CODE_PACKAGE_MANAGER_AUTO_UPDATE=1` で Homebrew 版を本体に更新させる道もあるが、それは結局「本体に更新させる」ことなので、最初からそうするほうが素直である)。

第四に、npm 版を選んでも配られる実体は同じネイティブバイナリである。違うのは起動の入口だけで、`@anthropic-ai/claude-code` の `bin` はネイティブバイナリを直に指すが、`@openai/codex` は `bin/codex.js`、`@github/copilot` は `npm-loader.js` と、Node のスクリプトをいったん踏んでから本体へ渡る。つまり npm 経由にしても速くも新しくもならず、Node.js への依存と、Node のバージョンを切り替えたときにグローバルパッケージが消えるという問題だけが増える。

引き換えに 1 つ諦めたものがある。`curl | sh` なのでチェックサムを固定できない。[外部アセットをチェックサムで固定する](#外部アセットをチェックサムで固定する)でやっていることの反対で、しかも同じ文書が第三者の Gist についてはリビジョンまで固定している。この非対称はどう正当化されるのか。

固定に意味があるのは「固定した版が使われ続ける」場合だけである。Gist の Skill は誰も更新しないので固定が効く。エージェント本体は自分を更新するので、インストーラを固定しても、入った直後に別の版へ入れ替わる。固定できるのは「一度きりの入口」だけで、そこから先は提供元を信頼するしかない。つまりここで諦めているのは、もともと得られないものである。

本当にバージョンを固定したいのであれば、まず自動更新を止めるところから始めることになる。

### インストーラに `.zshrc` を書き換えさせない

Codex と Copilot のインストーラは、インストール先が PATH に無いときに「シェルの設定ファイルへ `export PATH` の行を書き足す」という作りになっている。(Claude Code のインストーラも最後に `claude install` を呼んで「shell integration」を設定すると書いてあるが、中身はバイナリの側なので静的には追えない。手元で native 版を入れたマシンの `~/.config/zsh/.zshrc` を確かめたかぎり、書き足された痕跡は無かった。)書き足す先は `$SHELL` を見て決まる。`$SHELL` が zsh なら、Copilot は `$ZDOTDIR/.zprofile`、Codex は macOS で `~/.zprofile`、Linux で `~/.zshrc` を選ぶ (bash なら双方 `~/.bashrc` などになる)。Ubuntu の初回セットアップでは `chsh` の効果がログインし直すまで出ないので `$SHELL` はまだ bash であり、狙われるのは zsh に切り替わった後の apply からである。

`~/.zshrc` はこのリポジトリでは `~/.config/zsh/.zshrc` へのシンボリックリンクなので ([理由](#zshrc-をシンボリックリンクにしている))、これは chezmoi が管理しているファイルを直接書き換えられることを意味する。次の `chezmoi apply` で「書き換わっている」と聞かれることになり、[インストーラに設定を書き換えられたとき](chezmoi.md#インストーラに設定を書き換えられたとき)の手当てが要る。

書き足す先には `$ZDOTDIR/.zprofile` も含まれる。こちらも `dot_config/zsh/dot_zprofile.tmpl` として管理下にあるので、事情は同じである。

守りは 2 段にしてある。1 つめは、呼ぶ前に `~/.local/bin` を PATH に通しておくこと。Copilot はこれだけで何もしなくなる。Codex はもう少し込み入っていて、`add_to_path()` の早期 return には「PATH にあり、かつ他のパッケージマネージャ管理の codex を検出していない」という条件が付く。brew や npm で入れた codex が別にあると、PATH に通っていても書き込みにいく。

2 つめは、`command -v` で既に入っているものは呼ばないことである。競合が検出されるのは既存の codex がある場合に限られるので、そもそもインストーラが走らない。実際に問題が起きるのはこの 2 つをどちらも外したときだけだが、片方に寄りかかると崩れやすいので両方を残してある。

Copilot はそのうえ `[y/N]` を聞いてくるので、PATH を通しておかないと `chezmoi apply` が入力待ちで止まる。Codex のほうは `CODEX_NON_INTERACTIVE=1` でプロンプトを抑止している。

## Node.js を fnm で入れる

[nodejs.org のダウンロードページ](https://nodejs.org/ja/download)は nvm / fnm / Homebrew / Docker / ビルド済みバイナリなどを案内している。ここでは fnm を使っている。決め手は起動の速さではなく、**非対話シェルから `node` に到達できるかどうか**だった。

Claude Code のフックは `node <スクリプト>` のような素のコマンドで書かれる。たとえば Codex を Claude Code から呼ぶためのプラグイン ([openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc)) は、セッションの開始時・終了時・応答の終了時の 3 箇所でそれを走らせる。公式ドキュメントによれば、フックのコマンド文字列は macOS と Linux では `sh -c` に渡され、プロセスは Claude Code 自身の環境をそのまま継承する。

ここが肝心なところで、`sh` は zsh の設定ファイルを 1 つも読まない。つまり `node` への PATH は、フックが起動する時点で既に Claude Code の環境に入っていなければならない。その環境は Claude Code を起こしたシェルから受け継がれる。

そうすると `.zshrc` ではなく `.zshenv` に置く理由がはっきりする。`.zshrc` が読まれるのは対話シェルのときだけなので、ターミナルから起動した場合しか効かない。`.zshenv` はログインか否か・対話か否かを問わず、すべての zsh が読む。どちらの経路で Claude Code が起動されても PATH に入っているのは後者だけである。

そしてこの前提のもとでは、nvm のようにシェル関数として提供されるものは、フックの実行時点では手も足も出ない。`sh -c` の中に関数は存在しないからである。効くのは PATH に並んだ実体だけで、それをそのまま差し出せるかどうかが分かれ目になる。

nvm は 5000 行を超える POSIX シェルスクリプトで、`nvm` はコマンドではなくシェル関数として定義される。したがって `.zshenv` で PATH を通すには `nvm.sh` を読み込むしかない。Apple Silicon の Mac で実測すると、`zsh -f -c true` が 1.9ms なのに対し `zsh -f -c '. nvm.sh'` は 64.7ms だった。`.zshenv` は対話・非対話を問わずすべての zsh が読むので、この 63ms がシェルの起動ごとに乗る。

逃げ道は「デフォルト版の bin ディレクトリだけを固定パスで PATH に入れ、`nvm.sh` 自体は対話シェルでのみ読む」ことだが、ここで nvm と fnm に差が出る。

fnm は `$FNM_DIR/aliases/default` を実体へのシンボリックリンクとして張る。`fnm default 24` とすると `node-versions/v24.21.0/installation` を指すので、`.zshenv` には次の 1 行を足すだけで済む。プロセスの起動もファイルの読み込みも発生しない。

```zsh
path=(... "${FNM_DIR}/aliases/default/bin" ...)
```

nvm には相当するものが標準では無い。`$NVM_DIR/alias/default` は `24` と書いてあるだけのテキストファイルで、そこから実際のディレクトリを割り出すにはバージョン解決が要る。それを持っているのが `nvm.sh` なので、結局それを読むことになる。`NVM_SYMLINK_CURRENT=true` を設定すると `$NVM_DIR/current` が作られるが、nvm 自身が experimental としているうえ、`nvm use` のたびに全シェル共通のリンクを書き換えるため、複数のシェルを開いていると奪い合いになる。

対話シェルでは `.zshrc` で `fnm env --use-on-cd` を通してある。こちらはシェルごとに独立した PATH (`FNM_MULTISHELL_PATH`) を割り当てるので、`fnm use` が他のシェルに影響しない。この節は macOS では `brew shellenv` より後になければならない。`brew shellenv` は `/opt/homebrew/bin` を PATH の先頭に置き直すので、先に書くと Homebrew で `node` を入れているマシンでそちらが先に見つかる。

`FNM_DIR` を `.zshenv` で明示しているのは、fnm の既定が「その時点で何が存在するか」で変わるからである。`src/directories.rs` を読むと、`$XDG_DATA_HOME/fnm` が無ければ `~/.fnm` を、macOS ではさらに `~/Library/Application Support/fnm` を順に探し、見つかったほうを使う。以前 fnm を使ったことのあるマシンでは、古い置き場に吸い寄せられる。`.zshenv` の PATH と、Node を入れるスクリプトの置き場は同じところを指していなければならないので、継承した `XDG_DATA_HOME` にも過去の置き場にも左右されない形で固定してある。

固定しているのはメジャーバージョンだけで、その中の最新は fnm に選ばせている。パッチ版まで固定しても、セキュリティ修正のたびに手で追うことになるだけである。fnm 本体のほうは他の GitHub Releases 由来のツールと同じ扱いで、バージョンとチェックサムを固定してある。配布されているのは静的リンクの単一バイナリなので、[古いディストリでも動く形で配る](#古いディストリでも動く形で配る)で書いた glibc の下限の問題も起きない。

なお、Homebrew や apt で入れた `node` が残っていても実害は無い。システムのディレクトリより前に fnm 版が入るので、`.zshenv` と `.zshrc` のどちらの経路でも先に見つかる。例外は `~/.local/bin/node` で、こちらは fnm 版よりさらに前にあるため勝ってしまう ([ファイルの置き場と PATH の順序](#ファイルの置き場と-path-の順序))。

いずれの場合も「入れたはずの版と `node -v` が食い違う」と悩みやすいので、Node を入れた回に 1 度だけ知らせるようにしてある。ただし古いほうを消しはしない。Homebrew の `node` を外すと、そこに `npm -g` で入れたものまで一緒に消えるためである。

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

`chezmoi merge` による三方向マージも使えない。既定のマージツールが `vimdiff` なのに、vim は Brewfile にも Linux の `PACKAGES` 表にも入れていないからである。テキストエディタは扱わないという方針をそのまま通した結果である。vim を入れていない Linux では `chezmoi doctor` が次の警告を出す (macOS は `/usr/bin/vimdiff` を標準で持つので出ない)。

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

`~/.local/bin` に置いていた GitHub Releases 由来のバイナリ (`btm` `ghq` `uv` `uvx` `procs` `ouch` `yazi` `ya`) のほうは、`run_after_25-migrate-local-bin.sh` が片付ける。これは Linux でしか走らないので、macOS で旧構成から移る場合は自分で確認すること。消すのは、新しい置き場に同じ名前の実体があり、かつ自分で張ったシンボリックリンクでないものだけである。

この判定は名前しか見ていないので、同じ名前で自分が入れたものまで消える。たとえば uv の公式インストーラが置いた `~/.local/bin/uv` は消える。コマンド自体は新しい置き場のものが引き継ぐが、版はこのリポジトリで固定しているものに変わる。自分の版を使い続けたいなら、先に PATH の前のほうに来る別の場所へ移しておく。何を消したかは 1 件ずつログに出る。

## 既知の注意点

- 対象は Apple Silicon の macOS だけで、Intel Mac ではパッケージ導入スクリプトが最初に停止する。
- 以前の構成で `/etc/zshenv` に `ZDOTDIR` を書いていたとしても、残したまま動く。どちらの経路をたどっても `$ZDOTDIR/.zshenv` にたどり着くからである。不要なら root 権限で削除してかまわない。
- Ubuntu 22.04 の git は 2.34 で、新しめの設定がそのままでは通らない。`merge.conflictstyle` に指定している `zdiff3` は 2.35 から入った値で、知らない値を渡された古い git は警告して既定値に戻るのではなく、その場で終了する。マージも rebase も cherry-pick もできなくなるため、`~/.config/git/config` を生成するときに `git --version` を見て、届かなければ `diff3` に落としている。`push.autoSetupRemote` は 2.37 からで、こちらは知らないキーとして黙って無視される。古い環境では最初の push だけ `git push -u origin HEAD` を打つ。
- zsh-abbr v6 が内包する zsh-job-queue は、キューの置き場を `${TMPDIR:-/tmp}/zsh-job-queue` に決め打ちしている。`TMPDIR` がユーザごとに分かれていない Linux ではこれが全ユーザ共有になり、最初に zsh を起動した人が作ったディレクトリに 2 人目が書き込めず、略語がひとつも展開されなくなる。`.zshrc` で `JOB_QUEUE_TMPDIR` を指定して、ユーザごとに分けてある。
