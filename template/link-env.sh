#!/usr/bin/env bash
# Links this project's .venv to the workshop environment that setup.sh
# installed in ~/.venvs/ds-workshop. Run it once after cloning:
#
#   ./link-env.sh
#
# The project then uses .venv/bin/python like any other project, without a
# second copy of the packages. Safe to run again.

set -eu

ENV_DIR="$HOME/.venvs/ds-workshop"
cd "$(dirname "$0")"

if [ ! -x "$ENV_DIR/bin/python" ]; then
  echo "ERROR: the workshop environment is not installed ($ENV_DIR)."
  echo "Run the setup command from the workshop page first, then run ./link-env.sh again."
  exit 1
fi

if [ -L .venv ]; then
  if [ "$(readlink .venv)" = "$ENV_DIR" ]; then
    echo ".venv already points to $ENV_DIR"
  else
    echo ".venv pointed to $(readlink .venv). Pointing it to $ENV_DIR instead."
    rm .venv
    ln -s "$ENV_DIR" .venv
  fi
elif [ -e .venv ]; then
  echo "ERROR: .venv already exists here and is a real folder, not a link."
  echo "Delete it (rm -rf .venv) and run ./link-env.sh again."
  exit 1
else
  ln -s "$ENV_DIR" .venv
  echo "Linked .venv -> $ENV_DIR"
fi

.venv/bin/python -c 'import sys, pandas, sklearn, xgboost; print("Python", sys.version.split()[0], "with pandas, scikit-learn and XGBoost: OK")'
if [ -f requirements.txt ]; then
  echo "Checking the project's requirements.txt"
  .venv/bin/python -m pip install --quiet -r requirements.txt
  echo "All packages present."
fi
echo
echo "Ready. Start Claude here with: claude"
