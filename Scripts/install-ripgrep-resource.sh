#!/usr/bin/env bash
set -euo pipefail

ripgrep_version="${RIPGREP_VERSION:-15.1.0}"
archive_name="ripgrep-${ripgrep_version}-aarch64-apple-darwin.tar.gz"
download_url="https://github.com/BurntSushi/ripgrep/releases/download/${ripgrep_version}/${archive_name}"
tools_dir="Ruri/Resources/Tools"
temp_dir="$(mktemp -d)"

cleanup() {
  rm -rf "$temp_dir"
}
trap cleanup EXIT

mkdir -p "$tools_dir"
curl -fsSL "$download_url" -o "$temp_dir/$archive_name"
tar -xzf "$temp_dir/$archive_name" -C "$temp_dir"
install -m 0755 "$temp_dir/ripgrep-${ripgrep_version}-aarch64-apple-darwin/rg" "$tools_dir/rg"

echo "Installed ripgrep ${ripgrep_version} to ${tools_dir}/rg"
