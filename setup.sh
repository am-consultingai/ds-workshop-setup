#!/usr/bin/env bash
# Sets up the data science workshop on a Mac, or on Windows through WSL
# (Ubuntu): installs Claude Code, Python if needed, and the Python libraries,
# then checks everything.
#
#   ./setup.sh            create or update ~/.venvs/ds-workshop, install, check
#   ./setup.sh --fresh    delete that environment first and start clean
#   PYTHON=/path/to/python3.13 ./setup.sh    use a specific Python
#
# No Anaconda. Uses a standard Python virtual environment (venv) and pip.
# Steps that need an administrator password (sudo) are never run here: the
# script stops and prints the exact command to run, then you run it again.
# The environment lives in ~/.venvs/ds-workshop, outside this folder, so the
# workshop project can be downloaded later and use it through ./link-env.sh.
# Everything is printed and also saved to logs/setup_<date>_<time>.log.
# Written for the bash 3.2 that ships with macOS.

set -u -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
VENV="$HOME/.venvs/ds-workshop"
LOG_DIR="$HERE/logs"
LOG="$LOG_DIR/setup_$(date +%Y%m%d_%H%M%S).log"
FAILED_STEP_FILE="$LOG_DIR/.failed_step"
KERNEL_NAME="ds-workshop"
TOTAL_STEPS=8

FRESH=0
for arg in "$@"; do
  case "$arg" in
    --fresh) FRESH=1 ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg (try --help)"; exit 2 ;;
  esac
done

mkdir -p "$LOG_DIR"
rm -f "$FAILED_STEP_FILE"
export PYTHONUNBUFFERED=1 PIP_DISABLE_PIP_VERSION_CHECK=1

STEP=0
step() {  # step "Title"  — prints a numbered heading
  STEP=$((STEP + 1))
  echo
  echo "==> [$STEP/$TOTAL_STEPS] $1"
  CURRENT_STEP="$1"
}

run() {  # run cmd args...  — prints the command, runs it, records the step on failure
  echo "    \$ $*"
  local start=$SECONDS
  if "$@"; then
    echo "    done in $((SECONDS - start))s"
  else
    local code=$?
    echo "    command failed with exit code $code"
    echo "$CURRENT_STEP" > "$FAILED_STEP_FILE"
    return "$code"
  fi
}

fail() {  # fail "message"  — stops the setup at the current step
  echo "    ERROR: $1"
  echo "$CURRENT_STEP" > "$FAILED_STEP_FILE"
  return 1
}

python_version() {  # prints e.g. 3.13, or nothing if $1 isn't a working Python
  "$1" -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null
}

is_wsl() {  # true when running inside WSL on Windows
  grep -qi microsoft /proc/version 2>/dev/null
}

shell_rc() {  # the file your terminal reads at start, for the PATH line
  case "$(basename "${SHELL:-}")" in
    zsh)  echo "$HOME/.zshrc" ;;
    bash) if [ "$(uname -s)" = "Darwin" ]; then echo "$HOME/.bash_profile"; else echo "$HOME/.bashrc"; fi ;;
    *)    echo "" ;;
  esac
}

install_claude() {
  local bin="$HOME/.local/bin/claude"
  if command -v claude >/dev/null 2>&1; then
    echo "    found $(command -v claude) ($(claude --version 2>/dev/null | head -1))"
    return 0
  fi
  if [ ! -x "$bin" ]; then
    echo "    Not installed. Installing it with Anthropic's installer."
    run bash -c "curl -fsSL https://claude.ai/install.sh | bash" \
      || fail "the Claude Code installer failed. See the messages above." || return 1
  fi
  [ -x "$bin" ] || fail "the installer finished but $bin is missing." || return 1
  echo "    Installed: $bin ($("$bin" --version 2>/dev/null | head -1))"
  # The installer does not add ~/.local/bin to PATH. Add it once, so `claude`
  # starts from any folder in every new terminal window.
  local rc line='export PATH="$HOME/.local/bin:$PATH"'
  rc="$(shell_rc)"
  if [ -z "$rc" ]; then
    echo "    WARNING: unknown shell ${SHELL:-}. Add $HOME/.local/bin to your PATH yourself."
  elif grep -qs '\.local/bin' "$rc"; then
    echo "    PATH: $rc already includes ~/.local/bin"
  else
    printf '\n# Added by the data science workshop setup: lets you run claude from any folder\n%s\n' "$line" >> "$rc" \
      || fail "could not write to $rc. Add this line to it yourself: $line" || return 1
    echo "    PATH: added ~/.local/bin to $rc"
  fi
}

find_brew() {  # prints the brew path; it may not be on PATH right after installing
  local b
  for b in "$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -n "$b" ] && [ -x "$b" ] && { echo "$b"; return 0; }
  done
  return 1
}

need_homebrew() {  # stops the setup with Homebrew's official install command
  fail "this Mac needs Homebrew, which installs Python and the library XGBoost needs.
           Installing Homebrew needs your Mac password, so this script can't do it for you.
           Run this command, enter your Mac password when asked, and press Return to confirm:

             /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"

           It can take 5 to 15 minutes. Then paste the setup command again." || return 1
}

brew_on_path() {  # adds Homebrew's standard line to ~/.zprofile once, so brew works in new terminals
  local brew="$1" rc="$HOME/.zprofile"
  [ "$(basename "${SHELL:-}")" = "bash" ] && rc="$HOME/.bash_profile"
  if ! grep -qs 'brew shellenv' "$rc"; then
    printf '\n# Added by the data science workshop setup: Homebrew\neval "$(%s shellenv)"\n' "$brew" >> "$rc" \
      && echo "    PATH: added Homebrew to $rc"
  fi
}

need_sudo_linux() {  # stops the setup with the apt command for Python and venv
  local pkgs="$1"
  fail "Python needs to be installed with your Linux password, so this script can't do it for you.
           Run this command, enter your Linux password when asked (the one you set up for WSL):

             sudo apt update && sudo apt install -y $pkgs

           Then paste the setup command again." || return 1
}

version_ok() {  # 3.12 to 3.14
  case "$1" in 3.12|3.13|3.14) return 0 ;; *) return 1 ;; esac
}

find_python() {
  if [ -n "${PYTHON:-}" ]; then
    local pv
    pv="$(python_version "$PYTHON")"
    if [ -z "$pv" ]; then
      echo "    PYTHON=$PYTHON does not run"
      return 1
    elif ! version_ok "$pv"; then
      echo "    PYTHON=$PYTHON is Python $pv, need 3.12 to 3.14"
      return 1
    fi
    echo "    Using PYTHON=$PYTHON from the environment (Python $pv)"
    PY="$PYTHON"
    return 0
  fi
  local candidates="python3.13 python3.12 python3.14 python3
    /opt/homebrew/bin/python3.13 /opt/homebrew/bin/python3.12 /opt/homebrew/bin/python3.14
    /usr/local/bin/python3.13 /usr/local/bin/python3.12 /usr/local/bin/python3.14
    /Library/Frameworks/Python.framework/Versions/3.13/bin/python3.13
    /Library/Frameworks/Python.framework/Versions/3.12/bin/python3.12
    /Library/Frameworks/Python.framework/Versions/3.14/bin/python3.14"
  local c path v
  for c in $candidates; do
    path="$(command -v "$c" 2>/dev/null)" || continue
    # Apple's /usr/bin/python3 is 3.9, and calling it without the Command Line
    # Tools opens an install dialog. Skip it.
    if [ "$(uname -s)" = "Darwin" ] && [ "${path#/usr/bin/}" != "$path" ]; then
      echo "    skip  $path (Apple's system Python)"
      continue
    fi
    v="$(python_version "$path")"
    if [ -z "$v" ]; then
      echo "    skip  $path (does not run)"
    elif version_ok "$v"; then
      echo "    found $path (Python $v)"
      PY="$path"
      return 0
    else
      echo "    skip  $path (Python $v, need 3.12 to 3.14)"
    fi
  done
  return 1
}

main() {
  echo "Data science workshop setup  ·  $(date '+%Y-%m-%d %H:%M:%S')"
  echo "Folder: $HERE"
  echo "Log:    $LOG"

  step "Check this computer"
  echo "    System:       $(uname -s) $(uname -r), $(uname -m)"
  if [ "$(uname -s)" = "Darwin" ]; then
    echo "    macOS:        $(sw_vers -productVersion)"
    echo "    Homebrew:     $(find_brew || echo 'not installed')"
  elif is_wsl; then
    echo "    Windows:      WSL ($( (. /etc/os-release && echo "$PRETTY_NAME") 2>/dev/null || echo 'Linux'))"
    case "$HERE" in
      /mnt/*) echo "    WARNING: this folder is on the Windows drive ($HERE)."
              echo "    Installing there is very slow. Run the setup from your Linux home folder:"
              echo "      cd ~ and run the one-line command again." ;;
    esac
  else
    echo "    Linux:        $( (. /etc/os-release && echo "$PRETTY_NAME") 2>/dev/null || echo 'unknown')"
  fi
  echo "    Disk free:    $(df -h "$HOME" | awk 'NR==2 {print $4}') (needs about 2 GB)"
  run curl -sS -o /dev/null --max-time 15 -w "    PyPI reachable: HTTP %{http_code}\n" https://pypi.org/simple/pip/ \
    || fail "cannot reach pypi.org. Check the internet connection, VPN or proxy." || return 1

  step "Claude Code"
  install_claude || return 1

  step "Python 3.12, 3.13 or 3.14"
  local brew=""
  if [ "$(uname -s)" = "Darwin" ]; then
    # Homebrew is required on a Mac: XGBoost only finds libomp in Homebrew's folder.
    brew="$(find_brew)" || { need_homebrew; return 1; }
    echo "    Homebrew: $brew"
    brew_on_path "$brew"
  fi
  if ! find_python; then
    echo "    No suitable Python found."
    if [ -n "$brew" ]; then
      echo "    Installing Python 3.13 with Homebrew."
      run "$brew" install python@3.13 || fail "brew install python@3.13 failed. See the messages above." || return 1
      find_python || fail "Python was installed but can't be found. Open a new terminal and paste the setup command again." || return 1
    elif command -v apt-get >/dev/null 2>&1; then
      need_sudo_linux "python3 python3-venv" || return 1
    else
      fail "install Python 3.12, 3.13 or 3.14 with your system's package manager, then run this again." || return 1
    fi
  fi
  # Ubuntu and Debian ship venv's ensurepip in a separate package.
  if ! "$PY" -c 'import ensurepip, venv' 2>/dev/null; then
    if command -v apt-get >/dev/null 2>&1; then
      need_sudo_linux "python$(python_version "$PY")-venv" || return 1
    else
      fail "$PY has no venv/ensurepip module. Install the full Python, then run this again." || return 1
    fi
  fi
  echo "    Using: $PY ($("$PY" --version 2>&1))"
  local arch
  arch="$("$PY" -c 'import platform; print(platform.machine())')"
  echo "    Python architecture: $arch"

  step "OpenMP library for XGBoost (macOS only)"
  if [ "$(uname -s)" != "Darwin" ]; then
    echo "    Not macOS: not needed."
  else
    local omp_dir
    if [ "$arch" = "arm64" ]; then omp_dir="/opt/homebrew/opt/libomp/lib"; else omp_dir="/usr/local/opt/libomp/lib"; fi
    if [ -f "$omp_dir/libomp.dylib" ]; then
      echo "    found $omp_dir/libomp.dylib"
    else
      echo "    libomp is missing. Installing it with Homebrew."
      run "$brew" install libomp || fail "brew install libomp failed. See the messages above." || return 1
    fi
  fi

  step "Create the virtual environment"
  echo "    Location: $VENV"
  if [ -x "$HERE/.venv/bin/python" ]; then
    echo "    Note: $HERE/.venv is from an older version of this setup and is no longer used."
    echo "    To free about 1.5 GB: rm -rf \"$HERE/.venv\""
  fi
  if [ "$FRESH" = 1 ] && [ -d "$VENV" ]; then
    echo "    --fresh: deleting the old environment"
    run rm -rf "$VENV" || return 1
  fi
  if [ -x "$VENV/bin/python" ]; then
    local have want
    have="$(python_version "$VENV/bin/python")"
    want="$(python_version "$PY")"
    if [ "$have" != "$want" ]; then
      echo "    The environment uses Python $have, not $want. Recreating it."
      run rm -rf "$VENV" || return 1
    else
      echo "    Reusing the existing environment (Python $have). Use --fresh to start clean."
    fi
  fi
  if [ ! -x "$VENV/bin/python" ]; then
    mkdir -p "$(dirname "$VENV")"
    run "$PY" -m venv "$VENV" || fail "could not create the virtual environment." || return 1
  fi
  run "$VENV/bin/python" -m pip install --upgrade pip || return 1

  step "Install the workshop packages"
  echo "    From: $HERE/requirements.txt"
  sed -e '/^#/d' -e '/^$/d' -e 's/^/      /' "$HERE/requirements.txt"
  run "$VENV/bin/python" -m pip install -r "$HERE/requirements.txt" \
    || fail "package installation failed. The pip error above says which package." || return 1
  echo
  echo "    Installed versions:"
  "$VENV/bin/python" -m pip list --format=freeze | sed 's/^/      /'

  step "Register the Jupyter kernel '$KERNEL_NAME'"
  run "$VENV/bin/python" -m ipykernel install --user --name "$KERNEL_NAME" \
    --display-name "Python (ds-workshop)" || return 1

  step "Check the environment"
  run "$VENV/bin/python" "$HERE/check_env.py" || return 1
}

main 2>&1 | tee -a "$LOG"
STATUS=${PIPESTATUS[0]}

{
  echo
  echo "============================================================"
  if [ "$STATUS" -eq 0 ]; then
    echo "  SUCCESS!!  The workshop environment is ready."
    echo
    echo "  Installed in:  $VENV"
    echo "  Re-check:      \"$VENV/bin/python\" \"$HERE/check_env.py\""
    echo "  Log:           $LOG"
    echo
    echo "  Next: open a NEW terminal window and type  claude  to log in."
    echo
    echo "  Nothing else to install. When the workshop project is ready, you will"
    echo "  download it, run ./link-env.sh inside it once, and start Claude there."
  else
    echo "  FAILED at step: $(cat "$FAILED_STEP_FILE" 2>/dev/null || echo 'unknown')"
    echo
    echo "  Full log:   $LOG"
    echo "  Send the log file to the instructor if the message above doesn't explain it."
  fi
  echo "============================================================"
} | tee -a "$LOG"

exit "$STATUS"
