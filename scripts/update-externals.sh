#!/bin/sh
#
# .chezmoiexternal.toml.tmpl で固定しているバージョンとチェックサムを、上流の最新に
# 追随させる。対象は GitHub Releases のバイナリとフォント、それに Gist から取ってくる
# Claude Code の Skill である。
#
#   scripts/update-externals.sh           照合するだけで、何も書き換えない
#   scripts/update-externals.sh --diff    Skill の中身が上流でどう変わったのかを見る
#   scripts/update-externals.sh --write   テンプレートを書き換える
#
# 自動では走らない。何が変わるのかを見て、更新すると決めてから --write を付ける。
#
# 引数なしで実行すると、次の 2 つが分かる。
#
#   1. いま固定しているものより新しいリリース (Skill ならリビジョン) が出ているか
#   2. いま固定しているアセットが、宣言どおりのチェックサムのままか
#
# 2 が食い違っていたら、上流が既存のタグのアセットを差し替えたということである。
# その状態で新しいマシンをセットアップすると、chezmoi が SHA256 mismatch で
# apply 全体を中断する。--write で固定し直せば直る。
#
# 照合は x86_64 と aarch64 の両方について行う。片方のアセットだけが差し替えられる
# ことがあり、x86_64 しか見ていないと arm64 のマシンで初めて失敗する。
#
# Skill だけは扱いが違う。バージョン番号が無いため、Gist のリビジョン (コミット SHA)
# を URL に埋めて固定しており、API が返す最新のリビジョンと突き合わせる。中身は
# Claude Code が指示として読むテキストなので、--write の前に --diff で何が変わったのか
# を読む。

set -eu

cd "$(dirname "$0")/.."
TMPL=.chezmoiexternal.toml.tmpl
WRITE=0
DIFF=0

usage() {
    printf '%s\n' 'usage: scripts/update-externals.sh [--diff] [--write]'
    printf '%s\n' '  引数なし    固定している内容と上流を照合して表示します'
    printf '%s\n' '  --diff      Skill の固定中と最新の差分を表示します'
    printf '%s\n' '  --write     .chezmoiexternal.toml.tmpl を書き換えます'
}

for arg in "$@"; do
    case "$arg" in
        --write)   WRITE=1 ;;
        --diff)    DIFF=1 ;;
        -h|--help) usage; exit 0 ;;
        *) printf '不明な引数: %s\n' "$arg" >&2; usage >&2; exit 2 ;;
    esac
done

for c in curl jq; do
    command -v "$c" >/dev/null 2>&1 || { printf '%s が必要です\n' "$c" >&2; exit 1; }
done

if command -v sha256sum >/dev/null 2>&1; then
    sha256() { sha256sum | cut -d' ' -f1; }
else
    sha256() { shasum -a 256 | cut -d' ' -f1; }
fi

red()    { printf '\033[31m%s\033[0m' "$1"; }
green()  { printf '\033[32m%s\033[0m' "$1"; }
yellow() { printf '\033[33m%s\033[0m' "$1"; }

# GitHub API を呼ぶ。gh があれば認証付きで呼び、レート制限に余裕を持たせる。
api() {
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        gh api "repos/$1/releases/latest" --jq .tag_name 2>/dev/null || true
    else
        curl -fsSL "https://api.github.com/repos/$1/releases/latest" 2>/dev/null | jq -r '.tag_name // empty'
    fi
}

# Gist の最新リビジョン (コミット SHA) を返す。
gist_api() {
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        gh api "gists/$1" --jq '.history[0].version' 2>/dev/null || true
    else
        curl -fsSL "https://api.github.com/gists/$1" 2>/dev/null | jq -r '.history[0].version // empty'
    fi
}

# テンプレートの値を読む。x86_64 側は ':=' 行、arm64 側は字下げされた '=' 行。
get_x86() { sed -n 's/^{{- \$'"$1"' *:= "\([^"]*\)" -}}.*/\1/p' "$TMPL" | head -1; }
get_arm() { sed -n 's/^{{-   \$'"$1"' *= "\([^"]*\)" -}}.*/\1/p' "$TMPL" | head -1; }

# 値を書き換える。桁揃えの空白を壊さないよう、引用符の手前まではそのまま残す。
set_x86() {
    sed 's|^\({{- \$'"$1"' *:= "\)[^"]*\(" -}}\)|\1'"$2"'\2|' "$TMPL" > "$TMPL.new" && mv "$TMPL.new" "$TMPL"
}
set_arm() {
    sed 's|^\({{-   \$'"$1"' *= "\)[^"]*\(" -}}\)|\1'"$2"'\2|' "$TMPL" > "$TMPL.new" && mv "$TMPL.new" "$TMPL"
}

# name | repo | アセット名のパターン | アーキテクチャ別か
#   @V@ = バージョン (タグそのまま) / @A@ = x86_64|aarch64 / @G@ = amd64|arm64
TOOLS='
bottom|ClementTsang/bottom|bottom_@A@-unknown-linux-gnu.tar.gz|split
ghq|x-motemen/ghq|ghq_linux_@G@.zip|split
uv|astral-sh/uv|uv-@A@-unknown-linux-gnu.tar.gz|split
procs|dalance/procs|procs-@V@-@A@-linux.zip|split
ouch|ouch-org/ouch|ouch-@A@-unknown-linux-gnu.tar.gz|split
yazi|sxyazi/yazi|yazi-@A@-unknown-linux-gnu.zip|split
hackgen|yuru7/HackGen|HackGen_NF_@V@.zip|single
'

# --- Claude Code の Skills -------------------------------------------------
#
# 対象は .chezmoiexternal.toml.tmpl から拾う。Skill を足しても、ここに名前を
# 書き足す必要は無い。
#
# 宣言はこの形をしている。どのリビジョンに固定しているかは URL が持つ。
#
#   [".claude/skills/<名前>/SKILL.md"]
#       url = "https://gist.githubusercontent.com/<所有者>/<gist id>/raw/<リビジョン>/<ファイル名>"
#       [".claude/skills/<名前>/SKILL.md".checksum]
#           sha256 = "..."

skill_paths() {
    awk '/^\[".claude\/skills\/.*"\]$/ {
        s = $0; sub(/^\["/, "", s); sub(/"\]$/, "", s); print s
    }' "$TMPL"
}

# どのブロックの中かを見ながら、url と sha256 の値を取り出す。
skill_field() { # path url|sha256
    awk -v path="$1" -v field="$2" '
        /^[ \t]*\[".*\]$/ { blk = $0; sub(/^[ \t]+/, "", blk) }
        field == "url"    && blk == "[\"" path "\"]"          && /^[ \t]*url[ \t]*=/    { print; exit }
        field == "sha256" && blk == "[\"" path "\".checksum]" && /^[ \t]*sha256[ \t]*=/ { print; exit }
    ' "$TMPL" | sed 's/[^"]*"\([^"]*\)".*/\1/'
}

set_skill() { # path revision sha
    awk -v path="$1" -v rev="$2" -v sha="$3" '
        /^[ \t]*\[".*\]$/ { blk = $0; sub(/^[ \t]+/, "", blk) }
        blk == "[\"" path "\"]" && /^[ \t]*url[ \t]*=/ {
            sub(/\/raw\/[0-9a-f]+\//, "/raw/" rev "/")
        }
        blk == "[\"" path "\".checksum]" && /^[ \t]*sha256[ \t]*=/ {
            sub(/"[^"]*"/, "\"" sha "\"")
        }
        { print }
    ' "$TMPL" > "$TMPL.new" && mv "$TMPL.new" "$TMPL"
}

# https://gist.githubusercontent.com/<所有者>/<gist id>/raw/<リビジョン>/<ファイル名>
gist_id_of()  { printf '%s' "$1" | cut -d/ -f5; }
gist_rev_of() { printf '%s' "$1" | cut -d/ -f7; }
skill_url_at() { printf '%s' "$1" | sed 's|/raw/[0-9a-f]*/|/raw/'"$2"'/|'; }
short() { printf '%.8s' "$1"; }

asset_url() { # repo version pattern arch
    _a=x86_64; _g=amd64
    [ "$4" = arm ] && { _a=aarch64; _g=arm64; }
    _p=$(printf '%s' "$3" | sed -e "s|@V@|$2|g" -e "s|@A@|$_a|g" -e "s|@G@|$_g|g")
    printf 'https://github.com/%s/releases/download/%s/%s' "$1" "$2" "$_p"
}

# 取得できなかったときは何も返さない。curl の失敗をパイプで捨てると、空入力の
# ハッシュ (e3b0c442...) が取得できた値として通ってしまい、--write がそれを
# テンプレートに書き込んでしまう。
remote_sha() {
    _t=$(mktemp)
    if curl -fsSL "$1" -o "$_t" 2>/dev/null && [ -s "$_t" ]; then
        sha256 < "$_t"
    fi
    rm -f "$_t"
}

printf '%-9s %-12s %-12s %s\n' tool current latest state
printf '%s\n' '--------------------------------------------------------------'

CHANGED=0
STALE=0
UNKNOWN=0
TOOL_CHANGED=0
SKILL_CHANGED=0

for entry in $TOOLS; do
    name=${entry%%|*};   rest=${entry#*|}
    repo=${rest%%|*};    rest=${rest#*|}
    pattern=${rest%%|*}; kind=${rest#*|}

    cur=$(get_x86 "${name}Version")
    latest=$(api "$repo")
    if [ -z "$latest" ]; then
        printf '%-9s %-12s %-12s %s\n' "$name" "$cur" '-' "$(red '問い合わせに失敗')"
        UNKNOWN=$((UNKNOWN + 1))
        continue
    fi

    need_write=0
    if [ "$cur" = "$latest" ]; then
        ok=1
        [ "$(get_x86 "${name}Sha")" = "$(remote_sha "$(asset_url "$repo" "$cur" "$pattern" x86)")" ] || ok=0
        if [ "$kind" = split ]; then
            [ "$(get_arm "${name}Sha")" = "$(remote_sha "$(asset_url "$repo" "$cur" "$pattern" arm)")" ] || ok=0
        fi
        if [ "$ok" -eq 1 ]; then
            printf '%-9s %-12s %-12s %s\n' "$name" "$cur" "$latest" "$(green '最新 / ハッシュ一致')"
        else
            printf '%-9s %-12s %-12s %s\n' "$name" "$cur" "$latest" "$(red 'ハッシュ不一致 (上流が差し替えた)')"
            STALE=$((STALE + 1))
            need_write=1
        fi
    else
        printf '%-9s %-12s %-12s %s\n' "$name" "$cur" "$latest" "$(yellow '更新あり')"
        CHANGED=$((CHANGED + 1))
        TOOL_CHANGED=$((TOOL_CHANGED + 1))
        need_write=1
    fi

    [ "$WRITE" -eq 1 ] && [ "$need_write" -eq 1 ] || continue

    sha_x86=$(remote_sha "$(asset_url "$repo" "$latest" "$pattern" x86)")
    sha_arm=''
    [ "$kind" = split ] && sha_arm=$(remote_sha "$(asset_url "$repo" "$latest" "$pattern" arm)")
    if [ -z "$sha_x86" ] || { [ "$kind" = split ] && [ -z "$sha_arm" ]; }; then
        printf '          %s\n' "$(red 'アセットを取得できなかったので書き換えません')"
        printf '          %s\n' "アセット名の規則が変わっていないか確認してください: $(asset_url "$repo" "$latest" "$pattern" x86)"
        continue
    fi
    set_x86 "${name}Version" "$latest"
    set_x86 "${name}Sha" "$sha_x86"
    [ "$kind" = split ] && set_arm "${name}Sha" "$sha_arm"
    printf '          %s %s\n' "$(green '書き換えました')" "$latest"
done

printf '\n%-26s %-9s %-9s %s\n' skill current latest state
printf '%s\n' '--------------------------------------------------------------'

for path in $(skill_paths); do
    name=$(printf '%s' "$path" | cut -d/ -f3)
    url=$(skill_field "$path" url)
    cur=$(gist_rev_of "$url")
    gid=$(gist_id_of "$url")

    # URL にリビジョンが埋まっていなければ、そもそも固定できていない。そのまま
    # 書き換えると、URL は古いままで sha だけが新しくなるので、ここで止める。
    case "$cur" in
        *[!0-9a-f]* | '')
            printf '%-26s %-9s %-9s %s\n' "$name" '-' '-' \
                "$(red 'URL にリビジョンが無い')"
            printf '          %s\n' "$url"
            UNKNOWN=$((UNKNOWN + 1))
            continue
            ;;
    esac

    latest=$(gist_api "$gid")

    if [ -z "$latest" ]; then
        printf '%-26s %-9s %-9s %s\n' "$name" "$(short "$cur")" '-' "$(red '問い合わせに失敗')"
        UNKNOWN=$((UNKNOWN + 1))
        continue
    fi

    need_write=0
    if [ "$cur" = "$latest" ]; then
        # リビジョンはコミット SHA なので、同じリビジョンの中身が変わることはない。
        # 食い違うとしたら、記録した sha が間違っているか、Gist そのものが消えたときである。
        if [ "$(skill_field "$path" sha256)" = "$(remote_sha "$url")" ]; then
            printf '%-26s %-9s %-9s %s\n' "$name" "$(short "$cur")" "$(short "$latest")" \
                "$(green '最新 / ハッシュ一致')"
        else
            printf '%-26s %-9s %-9s %s\n' "$name" "$(short "$cur")" "$(short "$latest")" \
                "$(red 'ハッシュ不一致')"
            STALE=$((STALE + 1))
            need_write=1
        fi
    else
        printf '%-26s %-9s %-9s %s\n' "$name" "$(short "$cur")" "$(short "$latest")" \
            "$(yellow '更新あり')"
        CHANGED=$((CHANGED + 1))
        SKILL_CHANGED=$((SKILL_CHANGED + 1))
        need_write=1
    fi

    new_url=$(skill_url_at "$url" "$latest")

    # 差分を見せる。リビジョンが変わるときにファイル名まで変わることがあるので、
    # 取れなかったときはそう伝えて打ち切る。
    if [ "$DIFF" -eq 1 ] && [ "$cur" != "$latest" ]; then
        tmpd=$(mktemp -d)
        a="$name.$(short "$cur").md"
        b="$name.$(short "$latest").md"
        if curl -fsSL "$url" -o "$tmpd/$a" 2>/dev/null &&
           curl -fsSL "$new_url" -o "$tmpd/$b" 2>/dev/null; then
            # ラベルを短くするため、取得先のディレクトリの中で diff を取る。
            printf '\n'
            (cd "$tmpd" && diff -u "$a" "$b") || true
            printf '\n'
        else
            printf '          %s\n' "$(red '差分を取得できません。ファイル名が変わったのかもしれません')"
        fi
        rm -rf "$tmpd"
    fi

    [ "$WRITE" -eq 1 ] && [ "$need_write" -eq 1 ] || continue

    new_sha=$(remote_sha "$new_url")
    if [ -z "$new_sha" ]; then
        printf '          %s\n' "$(red '取得できなかったので書き換えません')"
        printf '          %s\n' "ファイル名まで変わっているかもしれません。URL を確認してください: $new_url"
        continue
    fi
    set_skill "$path" "$latest" "$new_sha"
    printf '          %s %s\n' "$(green '書き換えました')" "$(short "$latest")"
done

printf '%s\n' '--------------------------------------------------------------'

# 問い合わせに失敗したものがあるなら、まずそれを伝える。GitHub API は未認証だと
# 1 時間に 60 回しか呼べない。制限に達すると全件が '-' になる。
if [ "$UNKNOWN" -gt 0 ]; then
    printf '%s\n' "$(yellow "$UNKNOWN 件は上流への問い合わせに失敗しました。")"
    printf '%s\n' '  GitHub API のレート制限かもしれません。gh auth login で認証すると緩和されます。'
fi

if [ "$WRITE" -eq 1 ]; then
    printf '%s\n' '差分を確認してから commit してください。'
    printf '%s\n' '  git diff .chezmoiexternal.toml.tmpl'
    printf '%s\n' '  chezmoi apply --refresh-externals'
elif [ "$CHANGED" -gt 0 ] || [ "$STALE" -gt 0 ]; then
    [ "$TOOL_CHANGED" -gt 0 ] && printf '%d 件に新しいリリースがあります。\n' "$TOOL_CHANGED"
    [ "$SKILL_CHANGED" -gt 0 ] && printf '%d 件の Skill に新しいリビジョンがあります。\n' "$SKILL_CHANGED"
    [ "$STALE" -gt 0 ] && printf '%s\n' "$(red '固定しているアセットが差し替えられています。このままだと新しいマシンで apply が失敗します。')"
    if [ "$SKILL_CHANGED" -gt 0 ] && [ "$DIFF" -eq 0 ]; then
        printf '%s\n' 'Skill の中身は Claude Code が指示として読みます。まず差分を確認してください。'
        printf '%s\n' '  scripts/update-externals.sh --diff'
    fi
    printf '%s\n' '  scripts/update-externals.sh --write'
elif [ "$UNKNOWN" -eq 0 ]; then
    printf '%s\n' "$(green 'すべて最新で、ハッシュも一致しています。')"
fi
