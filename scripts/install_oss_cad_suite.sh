#!/usr/bin/env bash
set -euo pipefail

OSS_CAD_SUITE_DIR="${OSS_CAD_SUITE_DIR:-/opt/oss-cad-suite}"
OSS_CAD_SUITE_REPO="YosysHQ/oss-cad-suite-build"
SV2V_REPO="zachjs/sv2v"
INSTALL_BIN_DIR="/usr/local/bin"

need() {
	command -v "$1" >/dev/null 2>&1 || {
		echo "[FAIL] missing command: $1"
		exit 2
	}
}

os_name() {
	uname -s
}

arch_name() {
	uname -m
}

platform_label() {
	case "$(os_name):$(arch_name)" in
		Linux:x86_64) echo "linux-x64" ;;
		Linux:aarch64|Linux:arm64) echo "linux-arm64" ;;
		Darwin:x86_64) echo "darwin-x64" ;;
		Darwin:arm64) echo "darwin-arm64" ;;
		*)
			echo "[FAIL] unsupported platform: $(os_name) $(arch_name)"
			exit 2
			;;
	esac
}

require_brew_or_apt() {
	case "$(os_name)" in
		Linux)
			command -v apt-get >/dev/null 2>&1 || {
				echo "[FAIL] apt-get not found"
				exit 2
			}
			;;
		Darwin)
			need brew
			;;
		*)
			echo "[FAIL] unsupported platform: $(os_name)"
			exit 2
			;;
	esac
}

prompt_yes_no() {
	local prompt="$1"
	local answer
	local normalized
	while true; do
		read -r -p "$prompt [y/n]: " answer
		normalized="$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')"
		case "$normalized" in
			y|yes)
				return 0
				;;
			n|no)
				return 1
				;;
			*)
				echo "Please type 'y' or 'n'."
				;;
		esac
	done
}

report_existing_oss_cad_suite() {
	local has_existing=1
	if [[ -d "$OSS_CAD_SUITE_DIR" ]]; then
		echo "[WARN] Existing OSS CAD Suite directory found: $OSS_CAD_SUITE_DIR"
		has_existing=0
	fi

	for cmd in yosys verilator iverilog vvp; do
		if command -v "$cmd" >/dev/null 2>&1; then
			echo "[WARN] Existing $cmd found at: $(command -v "$cmd")"
			has_existing=0
		fi
	done

	if [[ $has_existing -eq 0 ]]; then
		echo "[WARN] This installer writes OSS CAD Suite to: $OSS_CAD_SUITE_DIR"
		echo "[WARN] This installer refreshes binary links in: $INSTALL_BIN_DIR"
	fi

	return "$has_existing"
}

report_existing_sv2v() {
	local has_existing=1
	if command -v sv2v >/dev/null 2>&1; then
		echo "[WARN] Existing sv2v found at: $(command -v sv2v)"
		has_existing=0
	fi
	if [[ -e "$INSTALL_BIN_DIR/sv2v" ]]; then
		echo "[WARN] Target path already exists: $INSTALL_BIN_DIR/sv2v"
		has_existing=0
	fi

	if [[ $has_existing -eq 0 ]]; then
		echo "[WARN] This installer writes sv2v to: $INSTALL_BIN_DIR/sv2v"
	fi

	return "$has_existing"
}

report_existing_netlistsvg() {
	local has_existing=1
	local npm_prefix
	if command -v netlistsvg >/dev/null 2>&1; then
		echo "[WARN] Existing netlistsvg found at: $(command -v netlistsvg)"
		has_existing=0
	fi

	npm_prefix="$(npm config get prefix 2>/dev/null || true)"
	if [[ -n "$npm_prefix" ]]; then
		echo "[INFO] npm global prefix: $npm_prefix"
	fi

	if [[ $has_existing -eq 0 ]]; then
		echo "[WARN] This installer will run: npm install -g netlistsvg"
	fi

	return "$has_existing"
}

maybe_install_component() {
	local component_name="$1"
	local report_func="$2"
	local install_func="$3"

	echo
	echo "== Install decision: $component_name =="
	if "$report_func"; then
		if ! prompt_yes_no "$component_name already appears to be installed. Reinstall/overwrite?"; then
			echo "[INFO] Skipping $component_name"
			return
		fi
	else
		if ! prompt_yes_no "No existing $component_name installation detected. Install now?"; then
			echo "[INFO] Skipping $component_name"
			return
		fi
	fi

	"$install_func"
}

fetch_latest_asset_url() {
	local repo="$1"
	local include_pattern="$2"
	python3 - "$repo" "$include_pattern" <<'PY'
import json
import sys
import urllib.request

repo = sys.argv[1]
pattern = sys.argv[2].lower()
url = f"https://api.github.com/repos/{repo}/releases/latest"

request = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json", "User-Agent": "project-venv-installer"})
with urllib.request.urlopen(request) as response:
    release = json.load(response)

for asset in release["assets"]:
    name = asset["name"].lower()
    if pattern in name:
        print(f"{asset['browser_download_url']}\t{asset['name']}")
        raise SystemExit(0)

raise SystemExit(f"No release asset matching {pattern!r} in {repo}")
PY
}

download_file() {
	local url="$1"
	local output="$2"
	curl -fsSL "$url" -o "$output"
}

install_oss_cad_suite() {
	local platform archive_url archive_name temp_dir extracted_dir
	platform="$(platform_label)"
	IFS=$'\t' read -r archive_url archive_name < <(fetch_latest_asset_url "$OSS_CAD_SUITE_REPO" "$platform")

	temp_dir="$(mktemp -d)"
	archive_name="${archive_name:-oss-cad-suite.tgz}"
	trap "rm -rf '$temp_dir'" RETURN

	echo "== 1) Download OSS CAD Suite (${platform}) =="
	download_file "$archive_url" "$temp_dir/$archive_name"

	echo
	echo "== 2) Install OSS CAD Suite system-wide =="
	sudo rm -rf "$OSS_CAD_SUITE_DIR"
	mkdir -p "$temp_dir/extract"
	tar -xzf "$temp_dir/$archive_name" -C "$temp_dir/extract"
	extracted_dir="$(find "$temp_dir/extract" -mindepth 1 -maxdepth 1 -type d | head -n1)"
	if [[ -z "$extracted_dir" ]]; then
		echo "[FAIL] could not find extracted OSS CAD Suite directory"
		exit 2
	fi
	sudo mv "$extracted_dir" "$OSS_CAD_SUITE_DIR"

	sudo install -d "$INSTALL_BIN_DIR"
	for tool in "$OSS_CAD_SUITE_DIR"/bin/*; do
		[[ -f "$tool" && -x "$tool" ]] || continue
		case "$(basename "$tool")" in
			python|python3|pip|pip3|tabbypy3|idle|pydoc|2to3|2to3-*)
				continue
				;;
		esac
		sudo rm -f "$INSTALL_BIN_DIR/$(basename "$tool")"
        echo '#!/bin/bash' | sudo tee "$INSTALL_BIN_DIR/$(basename "$tool")" > /dev/null
        echo "exec \"$tool\" "'"$@"' | sudo tee -a "$INSTALL_BIN_DIR/$(basename "$tool")" > /dev/null
        sudo chmod +x "$INSTALL_BIN_DIR/$(basename "$tool")"
	done

	hash -r || true

	echo
	echo "== 3) Verify OSS CAD Suite =="
	for cmd in yosys verilator iverilog vvp; do
		echo "which -a $cmd:"
		which -a "$cmd" || true
		echo
	done

	echo "verilator --version:"
	verilator --version
	echo
	echo "iverilog -V:"
	iverilog -V
	echo
	echo "vvp -V:"
	vvp -V
}

install_sv2v() {
	local platform asset_url asset_name temp_dir binary_path
	case "$(os_name):$(arch_name)" in
		Linux:x86_64) platform="linux" ;;
		Linux:aarch64|Linux:arm64) platform="linux" ;;
		Darwin:x86_64) platform="macos" ;;
		Darwin:arm64) platform="macos" ;;
		*)
			echo "[FAIL] unsupported sv2v platform: $(os_name) $(arch_name)"
			exit 2
			;;
	esac

	IFS=$'\t' read -r asset_url asset_name < <(fetch_latest_asset_url "$SV2V_REPO" "$platform")
	temp_dir="$(mktemp -d)"
	trap "rm -rf '$temp_dir'" RETURN

	echo
	echo "== 4) Install sv2v =="
	download_file "$asset_url" "$temp_dir/$asset_name"
	case "$asset_name" in
		*.tar.gz|*.tgz)
			tar -xzf "$temp_dir/$asset_name" -C "$temp_dir"
			;;
		*.zip)
			unzip -q "$temp_dir/$asset_name" -d "$temp_dir"
			;;
		*)
			cp "$temp_dir/$asset_name" "$temp_dir/sv2v"
			chmod +x "$temp_dir/sv2v"
			;;
	esac
	binary_path="$(find "$temp_dir" -type f -name sv2v -perm -111 | head -n1)"
	if [[ -z "$binary_path" ]]; then
		echo "[FAIL] could not find sv2v binary in release archive"
		exit 2
	fi
	sudo install -m 0755 "$binary_path" "$INSTALL_BIN_DIR/sv2v"

	echo "which -a sv2v:"
	which -a sv2v || true
	echo
	sv2v --version
}

npm_global_install() {
	local package_name="$1"
	local npm_prefix npm_bin user_prefix
	npm_bin="$(command -v npm || true)"
	if [[ -z "$npm_bin" ]]; then
		echo "[FAIL] npm not found in PATH"
		exit 2
	fi

	npm_prefix="$("$npm_bin" config get prefix 2>/dev/null || true)"
	if [[ -n "$npm_prefix" && -w "$npm_prefix" ]]; then
		"$npm_bin" install -g "$package_name"
	else
		if sudo "$npm_bin" --version >/dev/null 2>&1; then
			sudo "$npm_bin" install -g "$package_name"
		else
			user_prefix="${NPM_GLOBAL_PREFIX:-$HOME/.local}"
			mkdir -p "$user_prefix"
			"$npm_bin" config set prefix "$user_prefix"
			"$npm_bin" install -g "$package_name"
			echo "[WARN] Installed $package_name to user prefix: $user_prefix"
			echo "[WARN] Ensure $user_prefix/bin is on PATH to use $package_name"
		fi
	fi
}

install_netlistsvg() {
	echo
	echo "== 5) Install netlistsvg =="
	case "$(os_name)" in
		Linux)
			if ! command -v npm >/dev/null 2>&1; then
				sudo apt-get update
				sudo apt-get install -y nodejs npm
			fi
			npm_global_install netlistsvg
			;;
		Darwin)
			if ! command -v npm >/dev/null 2>&1; then
				brew install node
			fi
			npm_global_install netlistsvg
			;;
		*)
			echo "[FAIL] unsupported platform: $(os_name)"
			exit 2
			;;
	esac

	echo "which -a netlistsvg:"
	which -a netlistsvg || true
	echo
	netlistsvg --help >/dev/null 2>&1 || true
}

require_brew_or_apt
need curl
need tar
need python3

maybe_install_component "OSS CAD Suite" report_existing_oss_cad_suite install_oss_cad_suite
maybe_install_component "sv2v" report_existing_sv2v install_sv2v
maybe_install_component "netlistsvg" report_existing_netlistsvg install_netlistsvg

echo
echo "[OK] Done."