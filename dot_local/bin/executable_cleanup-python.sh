#!/bin/sh
#
# cleanup-python.sh - pyenv / miniforge を撤去して uv に一本化する。
#
# このスクリプトは chezmoi apply では「配置されるだけ」で自動実行されない。
# 削除するものが多く、取り返しがつかないため、意図して自分で実行したときだけ動く。
#
# 使い方:
#   ~/.local/bin/cleanup-python.sh
#   DRY_RUN=1 ~/.local/bin/cleanup-python.sh   何を消すかだけ表示する

set -eu

DRY_RUN="${DRY_RUN:-0}"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==>\033[0m %s\n' "$*" >&2; }

run() {
    if [ "$DRY_RUN" = "1" ]; then
        printf 'DRY   %s\n' "$*"
        return 0
    fi
    "$@"
}

if ! command -v uv >/dev/null 2>&1; then
    warn 'uv が見つかりません。先に chezmoi apply で uv を導入してください。'
    warn '移行先が無い状態で pyenv を消すと Python が使えなくなります。'
    exit 1
fi

# ---------------------------------------------------------------------------
# 失われるものを先に見せる
# ---------------------------------------------------------------------------
printf '\n'
log '撤去の対象'
printf '\n'

if command -v pyenv >/dev/null 2>&1; then
    printf '  [pyenv] 次のバージョンと、それらに紐づく venv が削除されます:\n'
    pyenv versions 2>/dev/null | sed 's/^/      /'
else
    printf '  [pyenv] 導入されていません\n'
fi
printf '\n'

if command -v conda >/dev/null 2>&1; then
    printf '  [conda] 次の環境が削除されます:\n'
    conda env list 2>/dev/null | sed 's/^/      /'
else
    printf '  [conda] 導入されていません\n'
fi
printf '\n'

# 消す先は PYENV_ROOT に従う。$HOME/.pyenv 決め打ちにすると、別の場所を
# 指している環境で「削除されます」と見せたものが残り、brew の pyenv だけが
# 消えるという中途半端な結果になる。見せる対象と消す対象は一致させる。
PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"

if [ -d "$PYENV_ROOT" ]; then
    printf '  [ディレクトリ] %s (%s)\n' "$PYENV_ROOT" "$(du -sh "$PYENV_ROOT" 2>/dev/null | cut -f1)"
fi
printf '\n'

# ---------------------------------------------------------------------------
# 確認
# ---------------------------------------------------------------------------
if [ "$DRY_RUN" != "1" ]; then
    printf '上記を削除します。取り消せません。続行しますか [y/N]: '
    # 非対話で呼ばれると read は EOF で非ゼロを返し、set -e がここで打ち切る。
    # 削除が起きない点では安全側だが、何も出さずに終了コード 1 で終わるので
    # 呼び出した側から原因が分からない。明示的に中止として扱う。
    if ! read -r answer; then
        printf '\n'
        log '入力を読めませんでした。中止します。'
        exit 0
    fi
    case "$answer" in
        [yY]|[yY][eE][sS]) ;;
        *) log '中止しました'; exit 0 ;;
    esac
fi

# ---------------------------------------------------------------------------
# 撤去
# ---------------------------------------------------------------------------
if command -v brew >/dev/null 2>&1; then
    if brew list --formula 2>/dev/null | grep -qx pyenv; then
        log 'brew の pyenv を削除します'
        run brew uninstall --ignore-dependencies pyenv
    fi
    if brew list --cask 2>/dev/null | grep -qx miniforge; then
        log 'brew の miniforge を削除します'
        run brew uninstall --cask miniforge
    fi
fi

if [ -d "$PYENV_ROOT" ]; then
    log "$PYENV_ROOT を削除します"
    run rm -rf "$PYENV_ROOT"
fi

for conda_dir in "$HOME/miniforge3" "$HOME/miniconda3" "$HOME/anaconda3"; do
    if [ -d "$conda_dir" ]; then
        log "$conda_dir を削除します"
        run rm -rf "$conda_dir"
    fi
done

if [ -f "$HOME/.condarc" ]; then
    log "$HOME/.condarc を削除します"
    run rm -f "$HOME/.condarc"
fi

log '完了しました'
printf '\n'
printf '今後の Python は uv で扱います:\n'
printf '    uv python install 3.13      Python 本体を入れる\n'
printf '    uv python list              入っているものを見る\n'
printf '    uv venv                     プロジェクトに venv を作る\n'
printf '    uv run script.py            venv を意識せず実行する\n'
printf '\n'
printf 'なお ~/.zprofile に pyenv の記述が残っている場合は手で削除してください\n'
printf '(chezmoi が管理するのは $ZDOTDIR 配下の設定のみです)。\n'
