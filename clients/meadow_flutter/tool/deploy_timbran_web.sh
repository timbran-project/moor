#!/usr/bin/env bash
# Copyright (C) 2026 Ryan Daum <ryan.daum@gmail.com>
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, version 3.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# this program. If not, see <https://www.gnu.org/licenses/>.

set -euo pipefail

cd "$(dirname "$0")/.."

timbran_root="${TIMBRAN_SITE_ROOT:-$HOME/timbran-site}"
subpath="${TIMBRAN_FLUTTER_SUBPATH:-meadow}"
api_base="${TIMBRAN_MOOR_API_URL:-}"
run_site_build=1
mode="release"

print_usage() {
    cat <<'EOF'
Usage: ./tool/deploy_timbran_web.sh [options]

Builds the Flutter web client under a subpath and copies it into the Timbran
site's public assets directory.

Default target:
  ~/timbran-site/public/meadow/

Options:
  --timbran-root PATH   Timbran site repo root (default: ~/timbran-site)
  --subpath NAME        URL/path segment to deploy under (default: meadow)
  --api-base URL        Default web-service base URL. If omitted, the app uses
                       same-origin on web (recommended for Timbran deploys).
  --skip-site-build     Do not run ~/timbran-site/build.sh after copying assets
  --debug               Build Flutter web in debug mode
  --profile             Build Flutter web in profile mode
  --release             Build Flutter web in release mode (default)
  -h, --help            Show this help

Examples:
  ./tool/deploy_timbran_web.sh
  ./tool/deploy_timbran_web.sh --subpath play
  ./tool/deploy_timbran_web.sh --api-base https://moo.timbran.org
  ./tool/deploy_timbran_web.sh --timbran-root ~/src/timbran-site --skip-site-build
EOF
}

while (($# > 0)); do
    case "$1" in
        --timbran-root)
            shift
            timbran_root="${1:-}"
            ;;
        --subpath)
            shift
            subpath="${1:-}"
            ;;
        --api-base)
            shift
            api_base="${1:-}"
            ;;
        --skip-site-build)
            run_site_build=0
            ;;
        --debug)
            mode="debug"
            ;;
        --profile)
            mode="profile"
            ;;
        --release)
            mode="release"
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            print_usage >&2
            exit 1
            ;;
    esac
    shift
done

if [[ -z "${timbran_root}" ]]; then
    echo "--timbran-root must not be empty" >&2
    exit 1
fi

if [[ -z "${subpath}" ]]; then
    echo "--subpath must not be empty" >&2
    exit 1
fi

if [[ ! -d "${timbran_root}" ]]; then
    echo "Timbran root does not exist: ${timbran_root}" >&2
    exit 1
fi

if [[ "${subpath}" == */* ]]; then
    echo "--subpath must be a single path segment, not a nested path: ${subpath}" >&2
    exit 1
fi

base_href="/${subpath}/"
target_dir="${timbran_root}/public/${subpath}"

echo "Building Flutter web (${mode}, wasm) with base href ${base_href}..."
build_cmd=(
    flutter build web "--${mode}" --wasm
    --base-href "${base_href}"
)
if [[ -n "${api_base}" ]]; then
    build_cmd+=( --dart-define "MOOR_DEFAULT_SERVER=${api_base}" )
fi
"${build_cmd[@]}"

echo "Copying build/web -> ${target_dir}"
mkdir -p "${target_dir}"
rsync -av --delete build/web/ "${target_dir}/"

if [[ "${run_site_build}" -eq 1 ]]; then
    if [[ ! -x "${timbran_root}/build.sh" ]]; then
        echo "Timbran build script not found or not executable: ${timbran_root}/build.sh" >&2
        exit 1
    fi
    echo "Rebuilding Timbran site..."
    (
        cd "${timbran_root}"
        ./build.sh
    )
fi

echo
echo "Flutter web client copied to:"
echo "  ${target_dir}"
echo
echo "Expected URL path:"
echo "  ${base_href}"
if [[ -n "${api_base}" ]]; then
    echo "Default API base:"
    echo "  ${api_base}"
else
    echo "Default API base:"
    echo "  same-origin (recommended)"
fi
echo
echo "Reminder: your web server still needs SPA fallback for ${base_href}* -> ${base_href}index.html"
