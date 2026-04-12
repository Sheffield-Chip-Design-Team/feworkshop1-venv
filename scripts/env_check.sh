#!/usr/bin/env bash
set -euo pipefail

ok()   { echo "[OK]   $1 - $2"; }
warn() { echo "[WARN] $1 - $2"; }
fail() { echo "[FAIL] $1 - $2"; exit 1; }

need_cmd() {
  local name="$1"
  local cmd="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$name" "$(command -v "$cmd")"
  else
    fail "$name" "Not found: $cmd"
  fi
}

run_cmd() {
  local cmd="$1"
  bash -lc "$cmd" 2>&1
}

os_name() {
  uname -s
}

os_release() {
  case "$(os_name)" in
    Linux)
      if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        echo "${ID:-linux} ${VERSION_ID:-unknown}"
      else
        echo "linux unknown"
      fi
      ;;
    Darwin)
      echo "macOS $(sw_vers -productVersion 2>/dev/null || echo unknown)"
      ;;
    *)
      echo "$(os_name) unknown"
      ;;
  esac
}

need_regex() {
  local name="$1"
  local cmd="$2"
  local regex="$3"
  local out
  out="$(run_cmd "$cmd")" || fail "$name" "Command failed: $cmd | Output: $out"
  if [[ "$out" =~ $regex ]]; then
    ok "$name" "$out"
  else
    fail "$name" "Unexpected output: $out"
  fi
}

# Compare semantic versions: returns 0 if $1 >= $2
ver_ge() {
  local have="$1"
  local need="$2"
  python3 - "$have" "$need" <<'PY'
import sys


def split_version(value: str):
    parts = []
    for chunk in value.split('.'):
        digits = ''
        for char in chunk:
            if char.isdigit():
                digits += char
            else:
                break
        parts.append(int(digits or 0))
    return parts


have = split_version(sys.argv[1])
need = split_version(sys.argv[2])
length = max(len(have), len(need))
have.extend([0] * (length - len(have)))
need.extend([0] * (length - len(need)))
raise SystemExit(0 if have >= need else 1)
PY
}

echo "== Shell environment =="
if [[ "${PATH:-}" == *".vscode-server"* ]]; then
  warn "VS Code Remote detected" "PATH is likely injected (this is normal), avoid relying on VIRTUAL_ENV"
fi
echo "PATH(head):"
echo "$PATH" | tr ':' '\n' | head -n 5

echo
echo "== OS check =="
detected_os="$(os_release)"
case "$(os_name)" in
  Linux)
    echo "Detected: $detected_os"
    if [[ -n "${ID:-}" && -n "${VERSION_ID:-}" ]]; then
      ok "Linux distro" "${ID} ${VERSION_ID}"
    else
      warn "Linux distro" "Unable to read /etc/os-release"
    fi
    ;;
  Darwin)
    echo "Detected: $detected_os"
    ok "macOS" "$detected_os"
    ;;
  *)
    fail "OS" "Unsupported platform: $(os_name)"
    ;;
esac

echo
echo "== Tooling presence =="
need_cmd "git" git
need_cmd "python3" python3
need_cmd "make" make
need_cmd "verilator" verilator
need_cmd "iverilog" iverilog
need_cmd "vvp" vvp
need_cmd "yosys" yosys
need_cmd "sv2v" sv2v
need_cmd "netlistsvg" netlistsvg

echo
echo "== Version checks =="

# pip
need_regex "pip3" 'python3 -m pip --version' 'pip[[:space:]]+[0-9]+\.'

# verilator >= 5.036 (cocotb 2.x requirement for Verilator flow)
ver_out="$(verilator --version)"
# Example: "Verilator 5.020 2024-01-01 ..."
have_ver="$(echo "$ver_out" | awk '{print $2}')"
need_ver="5.036"
if ver_ge "$have_ver" "$need_ver"; then
  ok "verilator (>= $need_ver)" "$ver_out"
else
  fail "verilator (>= $need_ver)" "have $have_ver, need $need_ver. Install a newer release with your platform's package manager or build from source."
fi

# fusesoc
need_cmd "fusesoc" fusesoc
ok "fusesoc" "$(fusesoc --version 2>&1 | head -n1)"

# cocotb: prefer cocotb-config (works for venv/pipx). Then import using cocotb-config's python.
need_cmd "cocotb-config" cocotb-config
ok "cocotb-config" "$(cocotb-config --version 2>&1)"

cocotb_py="$(cocotb-config --python-bin 2>/dev/null || true)"
if [[ -n "$cocotb_py" && -x "$cocotb_py" ]]; then
  ok "cocotb python" "$cocotb_py"
  cocotb_ver="$("$cocotb_py" -c "import cocotb; print(cocotb.__version__)" 2>&1)" \
    || fail "cocotb import" "Import failed using $cocotb_py | Output: $cocotb_ver"
  ok "cocotb import" "$cocotb_ver"
else
  # Fallback (should be rare): try system python import
  warn "cocotb python" "cocotb-config --python-bin not available; falling back to python3 import"
  need_regex "cocotb import" 'python3 -c "import cocotb; print(cocotb.__version__)"' '^[0-9]+\.'
fi

echo
echo "Done."
