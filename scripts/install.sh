#!/usr/bin/env bash
# Installs xcrashlytics from a GitHub release into ~/.local/bin (no sudo).
#
#   XCRASHLYTICS_VERSION      pin a release, e.g. 0.2.0 or v0.2.0 (default: latest)
#   XCRASHLYTICS_INSTALL_DIR  target directory (default: ~/.local/bin)
#
# Everything lives in main() and runs only on the last line, so a truncated
# `curl | sh` download cannot execute a partial script.
set -euo pipefail

# Global, not `local`: the EXIT trap runs after main() returns.
tmp=""
trap 'if [[ -n "${tmp}" ]]; then rm -rf "${tmp}"; fi' EXIT

main() {
  local repo="0xfirattamur/xcrashlytics"
  local install_dir="${XCRASHLYTICS_INSTALL_DIR:-${HOME}/.local/bin}"
  local tag="${XCRASHLYTICS_VERSION:-}"

  case "$(uname -s)" in
    Darwin) ;;
    *) echo "error: xcrashlytics releases support macOS only" >&2; return 1 ;;
  esac

  if [[ -n "${tag}" ]]; then
    [[ "${tag}" == v* ]] || tag="v${tag}"
  else
    local latest_url
    latest_url="$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/${repo}/releases/latest")"
    tag="${latest_url##*/}"
    [[ "${tag}" == v* ]] || { echo "error: no published release found" >&2; return 1; }
  fi

  local archive="xcrashlytics-${tag}-macos-universal.tar.gz"
  local base="https://github.com/${repo}/releases/download/${tag}"
  tmp="$(mktemp -d)"

  curl -fsSL "${base}/${archive}" -o "${tmp}/${archive}" \
    || { echo "error: could not download ${archive} — does release ${tag} exist?" >&2; return 1; }
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
}

main "$@"
