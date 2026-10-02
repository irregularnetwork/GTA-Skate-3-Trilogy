#!/usr/bin/env bash
set -Eeuo pipefail

package_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
files_dir="$package_dir"
bin_dir="$files_dir/bin"
setup_dir="$files_dir/setup"
game_dir="$files_dir/game"
converter="$setup_dir/iw4l-skate-convert.exe"
vice_city=""
xex=""
vice_city_given=0
xex_given=0
force_setup=0
no_launch=0

usage() {
    cat <<'USAGE'
Usage: ./run-linux.sh [--vice-city DIR] [--xex FILE_OR_DIR] [--setup] [--no-launch]

Runs the bundled Windows game with Wine. On first run, provide your original
Vice City PC install and extracted Skate 3 Xbox 360 files (default.xex + data).
USAGE
}

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

while (($#)); do
    case "$1" in
        --vice-city)
            (($# >= 2)) || fail "--vice-city needs a directory"
            vice_city=$2
            vice_city_given=1
            shift 2
            ;;
        --xex)
            (($# >= 2)) || fail "--xex needs a file or directory"
            xex=$2
            xex_given=1
            shift 2
            ;;
        --setup) force_setup=1; shift ;;
        --no-launch) no_launch=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) fail "Unknown option: $1 (try --help)" ;;
    esac
done

for command_name in wine winepath realpath cp; do
    command -v "$command_name" >/dev/null 2>&1 || fail "Required command not found: $command_name"
done

[[ -f "$bin_dir/reVC.exe" ]] || fail "Missing bundled game executable: $bin_dir/reVC.exe"
[[ -f "$converter" ]] || fail "Missing Skate 3 converter: $converter"

valid_vice_city() {
    local dir=$1
    [[ -d "$dir" && -f "$dir/models/gta3.img" && -f "$dir/models/gta3.dir" \
        && -f "$dir/data/gta_vc.dat" && -f "$dir/anim/ped.ifp" \
        && -f "$dir/TEXT/american.gxt" ]]
}

normalize_vice_city() {
    local path=$1
    path=${path#\"}; path=${path%\"}
    path=${path#\'}; path=${path%\'}
    if [[ -f "$path" && "${path##*/}" == "gta-vc.exe" ]]; then
        path=$(dirname -- "$path")
    fi
    if [[ -d "$path" ]]; then
        realpath -e -- "$path"
    else
        printf '%s' "$path"
    fi
}

normalize_xex() {
    local path=$1
    path=${path#\"}; path=${path%\"}
    path=${path#\'}; path=${path%\'}
    printf '%s' "$path"
}

valid_skate_data() {
    local dir=$1
    [[ -f "$dir/data/big/miscload.big" && -f "$dir/data/big/miscboot.big" \
        && -f "$dir/data/big/db.big" && -f "$dir/data/content/createacharacter.big" ]]
}

ready_to_play() {
    valid_vice_city "$game_dir" && [[ -f "$game_dir/skate-data/assets/private/skater.glb" ]]
}

if ((force_setup)) || ! ready_to_play; then
    [[ -n "$vice_city" ]] && vice_city=$(normalize_vice_city "$vice_city")
    [[ -n "$xex" ]] && xex=$(normalize_xex "$xex")
    while ! valid_vice_city "$vice_city"; do
        if [[ -n "$vice_city" ]]; then
            printf 'That does not look like the original PC Vice City folder.\n' >&2
            ((vice_city_given)) && fail "Invalid Vice City directory: $vice_city"
        fi
        read -r -p 'Path to your original Vice City folder or gta-vc.exe: ' vice_city
        vice_city=$(normalize_vice_city "$vice_city")
        [[ -n "$vice_city" ]] || continue
        [[ -d "$vice_city" ]] && vice_city=$(realpath -e -- "$vice_city")
    done

    while :; do
        if [[ -z "$xex" ]]; then
            read -r -p 'Path to Skate 3 default.xex or its extracted folder: ' xex
            xex=$(normalize_xex "$xex")
        fi
        [[ -d "$xex" ]] && xex="$xex/default.xex"
        if [[ -f "$xex" && "${xex##*/}" == "default.xex" ]]; then
            xex=$(realpath -e -- "$xex")
            if valid_skate_data "$(dirname -- "$xex")"; then break; fi
        fi
        ((xex_given)) && fail "Invalid or incomplete Skate 3 extraction: $xex"
        printf 'Could not find default.xex and the required data files. Try again.\n' >&2
        xex=""
    done

    mkdir -p -- "$game_dir"
    printf 'Copying Vice City and the bundled reVC files...\n'
    cp -a -- "$vice_city/." "$game_dir/"
    cp -a -- "$bin_dir/." "$game_dir/"

    printf 'Converting Skate 3 data with Wine...\n'
    xex_win=$(winepath -w "$xex")
    output_win=$(winepath -w "$game_dir/skate-data")
    wine "$converter" --xex "$xex_win" --out "$output_win" || fail "Skate 3 conversion failed"
    [[ -f "$game_dir/skate-data/assets/private/skater.glb" ]] || fail "Conversion did not produce skater.glb"
fi

if [[ -f "$game_dir/reVC.exe" ]]; then
    cp -au -- "$bin_dir/." "$game_dir/"
else
    fail "Setup did not produce $game_dir/reVC.exe"
fi

if ((no_launch)); then
    printf 'Setup complete.\n'
    exit 0
fi

printf 'Starting Vice City Skate with Wine...\n'
cd -- "$game_dir"
wine_overrides=${WINEDLLOVERRIDES:-}
[[ -n "$wine_overrides" ]] && wine_overrides+=";"
export WINEDLLOVERRIDES="${wine_overrides}dinput8=b"
exec wine ./reVC.exe