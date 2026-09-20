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

# Ctrl-C や途中終了で一時ファイルとテンプレートの書きかけを残さない。
cleanup() { rm -f "$TMPL.new"; }
trap cleanup EXIT INT TERM

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
#
# 置換値は上流のタグ名や API が返した SHA なので、こちらが中身を選べない。
# sed の置換文字列では & が「マッチ全体」、| が区切り文字、\ がエスケープと
# して働くので、そのまま埋めるとテンプレートが壊れる。先に無害化する。
sed_escape() { printf '%s' "$1" | sed -e 's/[&|\\]/\\&/g'; }

# 置換が 1 件も起きなかったことを検出する。sed も mv も、何も置換しなくても
# 成功で終わる。確かめないと「書き換えました」と表示しながら実際には
# 何も変わっていない、という状態が起きる (変数名を間違えたときなど)。
apply_sed() { # sed式
    sed "$1" "$TMPL" > "$TMPL.new" || { rm -f "$TMPL.new"; return 1; }
    if cmp -s "$TMPL" "$TMPL.new"; then
        rm -f "$TMPL.new"
        return 1
    fi
    mv "$TMPL.new" "$TMPL"
}

set_x86() {
    apply_sed 's|^\({{- \$'"$1"' *:= "\)[^"]*\(" -}}\)|\1'"$(sed_escape "$2")"'\2|'
}
set_arm() {
    apply_sed 's|^\({{-   \$'"$1"' *= "\)[^"]*\(" -}}\)|\1'"$(sed_escape "$2")"'\2|'
}

# name | repo | アセット名のパターン | アーキテクチャ別か
#   @V@ = バージョン (タグそのまま)
#   @A@ = x86_64|aarch64     Rust のターゲットトリプル
#   @G@ = amd64|arm64        Go の GOARCH
#   @L@ = linux|arm64        fnm 独自。x86_64 側だけ OS 名で、arm 側は arch 名になる
TOOLS='
bottom|ClementTsang/bottom|bottom_@A@-unknown-linux-gnu.tar.gz|split
ghq|x-motemen/ghq|ghq_linux_@G@.zip|split
uv|astral-sh/uv|uv-@A@-unknown-linux-gnu.tar.gz|split
procs|dalance/procs|procs-@V@-@A@-linux.zip|split
ouch|ouch-org/ouch|ouch-@A@-unknown-linux-gnu.tar.gz|split
yazi|sxyazi/yazi|yazi-@A@-unknown-linux-musl.zip|split
fnm|Schniz/fnm|fnm-@L@.zip|split
delta|dandavison/delta|delta-@V@-@A@-unknown-linux-gnu.tar.gz|split
dust|bootandy/dust|dust-@V@-@A@-unknown-linux-gnu.tar.gz|split
eza|eza-community/eza|eza_@A@-unknown-linux-gnu.tar.gz|split
sd|chmln/sd|sd-@V@-@A@-unknown-linux-musl.tar.gz|split
starship|starship/starship|starship-@A@-unknown-linux-musl.tar.gz|split
hackgen|yuru7/HackGen|HackGen_NF_@V@.zip|single
'

# tokei はここに載せない。v13 以降のリリースにはバイナリが添付されておらず、
# 最新のタグを見にいっても取得できるアセットが無い。載せると毎回「更新あり」と
# 出たうえで書き換えに失敗し続ける。実体のある v12.1.2 を手で固定してある。

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

# 置換が起きたことを確かめる。awk も mv も、何も置換しなくても成功で終わる。
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
    ' "$TMPL" > "$TMPL.new" || { rm -f "$TMPL.new"; return 1; }
    if cmp -s "$TMPL" "$TMPL.new"; then
        rm -f "$TMPL.new"
        return 1
    fi
    mv "$TMPL.new" "$TMPL"
}

# https://gist.githubusercontent.com/<所有者>/<gist id>/raw/<リビジョン>/<ファイル名>
gist_id_of()  { printf '%s' "$1" | cut -d/ -f5; }
gist_rev_of() { printf '%s' "$1" | cut -d/ -f7; }
skill_url_at() { printf '%s' "$1" | sed 's|/raw/[0-9a-f]*/|/raw/'"$2"'/|'; }
short() { printf '%.8s' "$1"; }

asset_url() { # repo version pattern arch
    _a=x86_64; _g=amd64; _l=linux
    [ "$4" = arm ] && { _a=aarch64; _g=arm64; _l=arm64; }
    _p=$(printf '%s' "$3" | sed -e "s|@V@|$2|g" -e "s|@A@|$_a|g" -e "s|@G@|$_g|g" -e "s|@L@|$_l|g")
    printf 'https://github.com/%s/releases/download/%s/%s' "$1" "$2" "$_p"
}

# 取得できなかったときは何も返さず、終了コード 1 を返す。curl の失敗をパイプで
# 捨てると、空入力のハッシュ (e3b0c442...) が取得できた値として通ってしまい、
# --write がそれをテンプレートに書き込んでしまう。
#
# 終了コードを返すのが要点である。値だけを見て「記録した sha と違う」と
# 判定すると、オフラインで実行しただけで全件が「上流がアセットを差し替えた」
# という最も深刻な警告に化ける。取得できなかったことと、取得できたが違って
# いたことは、まったく別の事態として扱う。
remote_sha() {
    _t=$(mktemp)
    if curl -fsSL "$1" -o "$_t" 2>/dev/null && [ -s "$_t" ]; then
        sha256 < "$_t"
        rm -f "$_t"
        return 0
    fi
    rm -f "$_t"
    return 1
}

# 記録した値と上流の値を突き合わせる。
#   0 一致 / 1 不一致 / 2 取得できなかった / 3 記録した値が無い
#
# 「記録が無い」を一致として扱ってはいけない。get_x86 も remote_sha も
# 失敗時は空文字を返すので、素朴に = で比べると空 = 空 が成立し、照合が
# 一度も行われていないのに「最新 / ハッシュ一致」と緑で出る。
compare_sha() { # 記録した値 URL
    [ -n "$1" ] || return 3
    _r=$(remote_sha "$2") || return 2
    [ "$1" = "$_r" ]
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
        # 0 一致 / 1 不一致 / 2 取得できなかった / 3 記録が無い のうち、
        # いちばん重いものを採る。取得できていないのに「差し替えられた」と
        # 言わないための区別である (compare_sha の注記を参照)。
        worst=0
        compare_sha "$(get_x86 "${name}Sha")" "$(asset_url "$repo" "$cur" "$pattern" x86)" || worst=$?
        if [ "$kind" = split ]; then
            compare_sha "$(get_arm "${name}Sha")" "$(asset_url "$repo" "$cur" "$pattern" arm)" || \
                { rc=$?; [ "$rc" -gt "$worst" ] && worst=$rc; }
        fi
        case "$worst" in
            0)
                printf '%-9s %-12s %-12s %s\n' "$name" "$cur" "$latest" "$(green '最新 / ハッシュ一致')"
                ;;
            1)
                printf '%-9s %-12s %-12s %s\n' "$name" "$cur" "$latest" "$(red 'ハッシュ不一致 (上流が差し替えた)')"
                STALE=$((STALE + 1))
                need_write=1
                ;;
            2)
                printf '%-9s %-12s %-12s %s\n' "$name" "$cur" "$latest" "$(yellow '最新 / アセットを取得できず未照合')"
                UNKNOWN=$((UNKNOWN + 1))
                ;;
            *)
                printf '%-9s %-12s %-12s %s\n' "$name" "$cur" "$latest" "$(red "テンプレートに \$${name}Sha がありません")"
                UNKNOWN=$((UNKNOWN + 1))
                ;;
        esac
    else
        printf '%-9s %-12s %-12s %s\n' "$name" "$cur" "$latest" "$(yellow '更新あり')"
        CHANGED=$((CHANGED + 1))
        TOOL_CHANGED=$((TOOL_CHANGED + 1))
        need_write=1
    fi

    [ "$WRITE" -eq 1 ] && [ "$need_write" -eq 1 ] || continue

    sha_x86=$(remote_sha "$(asset_url "$repo" "$latest" "$pattern" x86)") || sha_x86=''
    sha_arm=''
    if [ "$kind" = split ]; then
        sha_arm=$(remote_sha "$(asset_url "$repo" "$latest" "$pattern" arm)") || sha_arm=''
    fi
    if [ -z "$sha_x86" ] || { [ "$kind" = split ] && [ -z "$sha_arm" ]; }; then
        printf '          %s\n' "$(red 'アセットを取得できなかったので書き換えません')"
        printf '          %s\n' "アセット名の規則が変わっていないか確認してください: $(asset_url "$repo" "$latest" "$pattern" x86)"
        continue
    fi

    # 置換が実際に起きたかを確かめる。変数名を書き間違えていると、sed は
    # 何も置換せずに成功で終わるので、確かめないと「書き換えました」と
    # 表示しながら中身が変わらず、次回もまた「更新あり」が出続ける。
    wrote=1
    set_x86 "${name}Version" "$latest" || wrote=0
    set_x86 "${name}Sha" "$sha_x86" || wrote=0
    if [ "$kind" = split ]; then
        set_arm "${name}Sha" "$sha_arm" || wrote=0
    fi
    if [ "$wrote" -eq 1 ]; then
        printf '          %s %s\n' "$(green '書き換えました')" "$latest"
    else
        printf '          %s\n' "$(red '書き換えられませんでした')"
        printf '          %s\n' "テンプレートに \$${name}Version / \$${name}Sha の行があるか確認してください。"
        UNKNOWN=$((UNKNOWN + 1))
    fi
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
        # 食い違うとしたら、記録した sha が間違っているか、Gist そのものが消えた
        # ときである。取得できなかった場合と混同しないよう終了コードで分ける。
        rc=0
        compare_sha "$(skill_field "$path" sha256)" "$url" || rc=$?
        case "$rc" in
            0)
                printf '%-26s %-9s %-9s %s\n' "$name" "$(short "$cur")" "$(short "$latest")" \
                    "$(green '最新 / ハッシュ一致')"
                ;;
            2)
                printf '%-26s %-9s %-9s %s\n' "$name" "$(short "$cur")" "$(short "$latest")" \
                    "$(yellow '最新 / 取得できず未照合')"
                UNKNOWN=$((UNKNOWN + 1))
                ;;
            3)
                printf '%-26s %-9s %-9s %s\n' "$name" "$(short "$cur")" "$(short "$latest")" \
                    "$(red 'checksum の宣言がありません')"
                UNKNOWN=$((UNKNOWN + 1))
                ;;
            *)
                printf '%-26s %-9s %-9s %s\n' "$name" "$(short "$cur")" "$(short "$latest")" \
                    "$(red 'ハッシュ不一致')"
                STALE=$((STALE + 1))
                need_write=1
                ;;
        esac
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

    new_sha=$(remote_sha "$new_url") || new_sha=''
    if [ -z "$new_sha" ]; then
        printf '          %s\n' "$(red '取得できなかったので書き換えません')"
        printf '          %s\n' "ファイル名まで変わっているかもしれません。URL を確認してください: $new_url"
        continue
    fi
    if set_skill "$path" "$latest" "$new_sha"; then
        printf '          %s %s\n' "$(green '書き換えました')" "$(short "$latest")"
    else
        printf '          %s\n' "$(red '書き換えられませんでした')"
        printf '          %s\n' "宣言のパスが変わっていないか確認してください: $path"
        UNKNOWN=$((UNKNOWN + 1))
    fi
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
