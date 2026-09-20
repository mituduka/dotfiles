#!/bin/sh
#
# ログインシェルを zsh にし、XDG ディレクトリと履歴を整える。
#
# after_ なので .zshenv / .zshrc の配置が済んだあとに走る。
# テンプレート構文を含まないので .tmpl は付けない。
#
# run_once_ ではなく run_ にしてある (毎回走る)。chsh は sudo ではなく PAM で
# 当人のパスワードを要求するため、非対話の apply では通らないことがある。
#
# chezmoi が「実行済み」として記録するのは、終了コード 0 で終えたスクリプト
# だけである (非ゼロで終えたものは記録されず、次の apply で再試行される)。
# ところがこのスクリプトは、chsh に失敗しても警告だけ出して 0 で終える。
# 黙って apply 全体を落とさないためにそうしているのだが、run_once_ にすると
# その「失敗したが 0 で終えた回」が実行済みとして記録され、以後どれだけ
# apply しても再試行されず、警告も二度と出ないまま bash に取り残される。
# run_onchange_ でも同じで、失敗し続ける限りログインシェルの値が変わらないので
# ハッシュも変わらず再実行されない。到達したい状態を毎回確かめる形にする。
#
# 代償として、run_ のスクリプトは中身が変わっていなくても chezmoi status と
# chezmoi diff に毎回現れる (docs/chezmoi.md の「スクリプト」を参照)。
#
# 冪等なので繰り返して安全。既に zsh なら何もせずに終わる。

set -eu

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*" >&2; }

# ---------------------------------------------------------------------------
# 置き場は継承した XDG_* に従わず、$ZDOTDIR/.zshenv と同じ値に固定する。
#
# .zshenv は XDG_CONFIG_HOME などを継承値によらず ~/.config 以下に固定して
# いる。chezmoi が配置先をソース名から決める以上、設定の実在する場所と
# ツールが探す場所を一致させるにはそうするしかないからである
# (理由は .zshenv のコメントと docs/design.md を参照)。
#
# chezmoi の externals も同じで、宛先は .local/share/... というリテラルな
# パスであり、XDG_DATA_HOME が何であろうとそこに降りる。
#
# したがってスクリプト側だけが継承値に従うと、作るディレクトリと実際に
# 使われるディレクトリがずれる。XDG_DATA_HOME=/opt/data のような環境から
# chezmoi apply したときにだけ表に出るので、気づきにくい。
# ---------------------------------------------------------------------------
CACHE_HOME="$HOME/.cache"
STATE_HOME="$HOME/.local/state"
DATA_HOME="$HOME/.local/share"

# ---------------------------------------------------------------------------
# compinit の zcompdump 置き場。これが無いと補完キャッシュを書き出せず、
# シェル起動のたびに補完定義をフル再構築することになる。
#
# dotfiles/bin は externals が GitHub Releases のバイナリを置く先で、
# $ZDOTDIR/.zshenv が PATH の末尾に入れている。空でも先に作っておく。
# ---------------------------------------------------------------------------
mkdir -p \
    "$CACHE_HOME/zsh" \
    "$STATE_HOME/zsh" \
    "$DATA_HOME/dotfiles/bin" \
    "$HOME/.local/bin"

# ---------------------------------------------------------------------------
# 履歴の移送。旧構成では $ZDOTDIR 直下に置いていたものを XDG の state へ移す。
# 追記ではなく「移送先が無いときだけコピー」にして、二重実行で履歴が
# 重複しないようにしている。
# ---------------------------------------------------------------------------
OLD_HISTFILE="$HOME/.config/zsh/.zsh_history"
NEW_HISTFILE="$STATE_HOME/zsh/history"
if [ -f "$OLD_HISTFILE" ] && [ ! -f "$NEW_HISTFILE" ]; then
    log "履歴を移送します: $OLD_HISTFILE -> $NEW_HISTFILE"
    cp "$OLD_HISTFILE" "$NEW_HISTFILE"
fi

# ---------------------------------------------------------------------------
# ログインシェルを zsh にする
# ---------------------------------------------------------------------------
zsh_path="$(command -v zsh || true)"
if [ -z "$zsh_path" ]; then
    warn 'zsh が見つかりません。ログインシェルの変更をスキップします。'
    exit 0
fi

# $SHELL は親プロセスから継承した値にすぎず、実際のログインシェルとは
# 限らない (tmux やコンテナの中、su した直後などでズレる)。
# passwd エントリを直接見る。
current_shell=''
if command -v getent >/dev/null 2>&1; then
    current_shell="$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7 || true)"
elif [ "$(uname -s)" = Darwin ] && command -v dscl >/dev/null 2>&1; then
    current_shell="$(dscl . -read "/Users/$(id -un)" UserShell 2>/dev/null | awk '{print $2}' || true)"
fi
if [ -z "$current_shell" ]; then
    current_shell="${SHELL:-}"
fi

if [ "$current_shell" = "$zsh_path" ]; then
    # 毎回走るので、到達済みのときは黙って終わる。
    exit 0
fi

# chsh は /etc/shells に載っているシェルしか受け付けない。
if [ -r /etc/shells ] && ! grep -qxF "$zsh_path" /etc/shells; then
    if [ "$(id -u)" -eq 0 ]; then
        log "/etc/shells に $zsh_path を追記します"
        printf '%s\n' "$zsh_path" >> /etc/shells
    elif command -v sudo >/dev/null 2>&1 && { [ -t 0 ] || sudo -n true 2>/dev/null; }; then
        # このスクリプトの他の失敗経路はすべて警告に留めているのに、ここだけ
        # 素で実行すると sudo の失敗で apply 全体が落ちる。しかも毎回走るので
        # 毎回落ちる。端末が無く、かつパスワードがキャッシュされてもいないなら
        # そもそも試さない (試せばパスワード待ちで apply が止まる)。
        log "/etc/shells に $zsh_path を追記します (sudo)"
        if ! printf '%s\n' "$zsh_path" | sudo tee -a /etc/shells >/dev/null; then
            warn "/etc/shells への追記に失敗しました。次を手動で実行してください:"
            warn "  echo $zsh_path | sudo tee -a /etc/shells"
            exit 0
        fi
    else
        warn "$zsh_path が /etc/shells にありません。手動で追記してください。"
        exit 0
    fi
fi

# chsh は sudo ではなく PAM で当人のパスワードを要求する。したがって
# 実行するのは入力できる見込みがあるときだけにする。
#
#   - 端末がある        : 聞かれても答えられる
#   - root で動いている : そもそも聞かれない (コンテナやプロビジョニング)
#
# このスクリプトは毎回走るので、どちらでもないときに無条件で実行すると、
# apply のたびにパスワード待ちで止まることになる。
#
# 一方で、到達していないことは毎回知らせる。黙って bash のまま取り残される
# のを防ぐのが run_ にしている理由なので、警告は省かない。
if [ -t 0 ] || [ "$(id -u)" -eq 0 ]; then
    log "ログインシェルを $zsh_path に変更します"
    if ! chsh -s "$zsh_path"; then
        warn 'chsh に失敗しました。次のコマンドを手動で実行してください:'
        warn "  chsh -s $zsh_path"
    fi
else
    warn "ログインシェルが zsh になっていません (現在: ${current_shell:-不明})。"
    warn '端末のある環境で次を実行してください:'
    warn "  chsh -s $zsh_path"
fi
