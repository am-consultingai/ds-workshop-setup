#!/usr/bin/env bash
# Sets up the data science workshop environment on a Mac, then checks it.
#
#   ./setup.sh            create or update .venv here, install, check
#   ./setup.sh --fresh    delete .venv first and start clean
#   PYTHON=/path/to/python3.13 ./setup.sh    use a specific Python
#
# No Anaconda. Uses a standard Python virtual environment (venv) and pip.
# Everything is printed and also saved to logs/setup_<date>_<time>.log.
# Written for the bash 3.2 that ships with macOS.

set -u -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
VENV="$HERE/.venv"
LOG_DIR="$HERE/logs"
LOG="$LOG_DIR/setup_$(date +%Y%m%d_%H%M%S).log"
FAILED_STEP_FILE="$LOG_DIR/.failed_step"
KERNEL_NAME="ds-workshop"
TOTAL_STEPS=7

FRESH=0
for arg in "$@"; do
  case "$arg" in
    --fresh) FRESH=1 ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
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
    echo "    Homebrew:     $(command -v brew || echo 'not installed')"
  else
    echo "    Note: this script is written for macOS; continuing anyway."
  fi
  echo "    Disk free:    $(df -h "$HERE" | awk 'NR==2 {print $4}') (needs about 2 GB)"
  run curl -sS -o /dev/null --max-time 15 -w "    PyPI reachable: HTTP %{http_code}\n" https://pypi.org/simple/pip/ \
    || fail "cannot reach pypi.org. Check the internet connection, VPN or proxy." || return 1

  step "Find Python 3.12, 3.13 or 3.14"
  find_python || fail "no suitable Python found.
           Install Python 3.13 from https://www.python.org/downloads/macos/
           or with Homebrew: brew install python@3.13
           then run this script again." || return 1
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
    elif command -v brew >/dev/null 2>&1; then
      echo "    libomp is missing. Installing it with Homebrew."
      run brew install libomp || fail "brew install libomp failed. See the messages above." || return 1
    else
      echo "    WARNING: libomp not found at $omp_dir and Homebrew is not installed."
      echo "    Everything else will install, but XGBoost will not load."
      echo "    The environment check at the end will show this as a failure."
    fi
  fi

  step "Create the virtual environment"
  if [ "$FRESH" = 1 ] && [ -d "$VENV" ]; then
    echo "    --fresh: deleting the old environment"
    run rm -rf "$VENV" || return 1
  fi
  if [ -x "$VENV/bin/python" ]; then
    local have want
    have="$(python_version "$VENV/bin/python")"
    want="$(python_version "$PY")"
    if [ "$have" != "$want" ]; then
      echo "    Existing .venv uses Python $have, not $want. Recreating it."
      run rm -rf "$VENV" || return 1
    else
      echo "    Reusing existing .venv (Python $have). Use --fresh to start clean."
    fi
  fi
  if [ ! -x "$VENV/bin/python" ]; then
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
    echo "  Start it:   source \"$VENV/bin/activate\""
    echo "  Notebooks:  jupyter lab   (choose the kernel 'Python (ds-workshop)')"
    echo "  Re-check:   \"$VENV/bin/python\" \"$HERE/check_env.py\""
    echo "  Log:        $LOG"
  else
    echo "  FAILED at step: $(cat "$FAILED_STEP_FILE" 2>/dev/null || echo 'unknown')"
    echo
    echo "  Full log:   $LOG"
    echo "  Send the log file to the instructor if the message above doesn't explain it."
  fi
  echo "============================================================"
} | tee -a "$LOG"

exit "$STATUS"
