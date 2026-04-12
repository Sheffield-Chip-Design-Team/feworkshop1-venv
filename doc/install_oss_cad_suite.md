# `install_oss_cad_suite.sh` Explained

This script installs the main hardware design tools for this template in one place.
It is meant to work on Linux systems such as WSL Ubuntu and on macOS.

## What It Installs

The script installs:

- OSS CAD Suite, system-wide
- `sv2v`
- `netlistsvg`

OSS CAD Suite provides tools such as:

- `verilator`
- `iverilog`
- `vvp`
- `yosys`

That is why the README tells you to run one installer instead of several separate ones.

## High-Level Flow

The script does these steps:

1. Detects the operating system and CPU architecture.
2. Checks that the host platform is supported.
3. Checks existing installs and asks whether to install each component (`y/n`).
4. Downloads the latest OSS CAD Suite release for that platform.
5. Extracts it and moves it into `/opt/oss-cad-suite`.
6. Creates command wrappers in `/usr/local/bin` for the executable tools.
7. Downloads and installs `sv2v`.
8. Installs `netlistsvg` with `npm`.
9. Verifies that the expected commands are available.

## Interactive Behavior

Before each component install (`OSS CAD Suite`, `sv2v`, `netlistsvg`), the script:

- checks whether the component already appears to exist
- prints where it was found
- prompts for confirmation with `y` or `n`

That lets users skip a component they already have.

## Step-by-Step Breakdown

### 1) Shell Safety Settings

```bash
set -euo pipefail
```

This makes the script stop quickly if something goes wrong.

- `-e` stops on the first failing command.
- `-u` stops if the script uses an unset variable.
- `pipefail` makes a pipeline fail if any command in it fails.

For a beginner, this is useful because it avoids silent failures.

### 2) Configuration Variables

The script starts with a few variables:

- `OSS_CAD_SUITE_DIR` defaults to `/opt/oss-cad-suite`
- `OSS_CAD_SUITE_REPO` points to the OSS CAD Suite GitHub repository
- `SV2V_REPO` points to the sv2v GitHub repository
- `INSTALL_BIN_DIR` defaults to `/usr/local/bin`

These values control where the tools are downloaded from and where they are installed.

### 3) Checking for Required Commands

The `need` function checks whether a command exists on the system.

The script uses it to confirm that commands such as `curl`, `tar`, and `python3` are available before it tries to download or unpack anything.

### 4) Operating System and Architecture Detection

The `os_name` and `arch_name` helpers run `uname` to find:

- the operating system, such as `Linux` or `Darwin`
- the CPU architecture, such as `x86_64` or `arm64`

The `platform_label` function converts that information into the release naming format used by OSS CAD Suite.

Examples:

- `Linux` + `x86_64` becomes `linux-x64`
- `Linux` + `arm64` becomes `linux-arm64`
- `Darwin` + `x86_64` becomes `darwin-x64`
- `Darwin` + `arm64` becomes `darwin-arm64`

If the platform is not one of those, the script exits with an error.

### 5) Checking Whether the Platform Is Supported

The `require_brew_or_apt` function ensures the script is running on a system that has either:

- `apt-get` on Linux
- `brew` on macOS

This does not install those package managers. It only checks that the host has the expected package-management setup.

### 6) Finding the Latest Release Asset

The `fetch_latest_asset_url` function uses the GitHub releases API to look up the latest release and find a download asset whose name matches the current platform.

This is what makes the installer avoid hardcoded version numbers.

Instead of saying “download version X,” the script always tries to fetch the newest release that matches your system.

### 7) Downloading a File

The `download_file` helper wraps `curl`.

It downloads a file from a URL and saves it to a local path.

The script uses this for both the OSS CAD Suite archive and the sv2v release archive.

### 8) Installing OSS CAD Suite

The `install_oss_cad_suite` function handles the largest part of the job.

It does the following:

- figures out the correct OSS CAD Suite release for the current platform
- downloads the archive into a temporary directory
- extracts the archive
- moves the extracted folder into `/opt/oss-cad-suite`
- creates executable wrapper scripts in `/usr/local/bin`

The wrapper step matters because it makes commands like `verilator` and `yosys` available on your `PATH` without requiring you to manually edit shell startup files.

#### Why system-wide installation?

OSS CAD Suite is installed system-wide because the script is intended to set up the base toolchain for the machine, not just for one Python virtual environment.

That makes the tools available to the whole project and to other shell sessions.

### 9) Installing `sv2v`

The `install_sv2v` function does a similar release-based install for `sv2v`.

It:

- selects the correct release asset for Linux or macOS
- downloads the archive
- extracts it
- finds the `sv2v` binary
- installs it into `/usr/local/bin/sv2v`

`sv2v` is a SystemVerilog-to-Verilog converter.
It is useful when a flow needs to convert SystemVerilog source into plain Verilog.

### 10) Installing `netlistsvg`

The `install_netlistsvg` function installs `netlistsvg` with `npm`.

If `npm` is not already installed:

- on Linux, the script installs `nodejs` and `npm` using `apt-get`
- on macOS, the script installs Node.js using Homebrew

Then it runs `npm install -g netlistsvg`.

`netlistsvg` turns a Yosys JSON netlist into an SVG schematic.

### 11) Verifying the Installation

At the end, the script checks that these commands are available:

- `yosys`
- `verilator`
- `iverilog`
- `vvp`
- `sv2v`
- `netlistsvg`

It also prints version information where possible.

This verification step is important because it helps you catch PATH or install problems immediately.

## What Beginners Should Expect

When the script succeeds, you should be able to run commands such as:

```bash
verilator --version
iverilog -V
vvp -V
yosys --version
sv2v --version
netlistsvg --help
```

If one of those commands fails, the most likely causes are:

- you are missing `sudo` access
- `curl`, `tar`, `python3`, `npm`, or `brew` is missing
- the platform is not supported by the release asset lookup
- the network cannot reach GitHub
- you are in a minimal Docker container without `sudo`

## Important Notes

- The script is meant for WSL Ubuntu and macOS.
- It is not intended for Windows directly.
- It installs tools system-wide, so you may need admin permissions.
- In minimal Docker images, install `sudo` first or run in an environment where `sudo` exists.
- Coraltb is still installed separately by `install_coraltb.sh`.

## Related Files

- [README.md](../README.md)
- [scripts/install_oss_cad_suite.sh](../scripts/install_oss_cad_suite.sh)