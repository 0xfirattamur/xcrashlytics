#!/usr/bin/env bash
set -euo pipefail

repo="0xfirattamur/xcrashlytics"
install_dir="${XCRASHLYTICS_INSTALL_DIR:-${HOME}/.local/bin}"
release_url="https://github.com/${repo}/releases/latest"

case "$(uname -s)" in
  Darwin) ;;
  *) echo "error: xcrashlytics releases support macOS only" >&2; exit 1 ;;
esac

latest_url="$(curl -fsSL -o /dev/null -w '%{url_effective}' "${release_url}")"
tag="${latest_url##*/}"
[[ "${tag}" == v* ]] || { echo "error: no published release found" >&2; exit 1; }

archive="xcrashlytics-${tag}-macos-universal.tar.gz"
base="https://github.com/${repo}/releases/download/${tag}"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

curl -fsSL "${base}/${archive}" -o "${tmp}/${archive}"
curl -fsSL "${base}/${archive}.sha256" -o "${tmp}/${archive}.sha256"
(
  cd "${tmp}"
  shasum -a 256 -c "${archive}.sha256"
  tar -xzf "${archive}"
)

mkdir -p "${install_dir}"
install -m 755 "${tmp}/xcrashlytics" "${install_dir}/xcrashlytics"
printf 'Installed xcrashlytics %s to %s\n' "${tag}" "${install_dir}/xcrashlytics"
if [[ ":${PATH}:" != *":${install_dir}:"* ]]; then
  printf 'Add %s to PATH if needed.\n' "${install_dir}" >&2
fi
