# Workshop setup test

Sets up Python for the workshop on a Mac without Anaconda, and checks that it works.

```bash
git clone https://github.com/am-consultingai/ds-workshop-setup.git
cd ds-workshop-setup
./setup.sh
```

It ends with **SUCCESS!!** or **FAILED at step: …**. Either way, the full log is in `logs/`.

## What you need first

- **Python 3.12, 3.13 or 3.14.** Not Apple's built-in `/usr/bin/python3`, which is 3.9. Get it from [python.org](https://www.python.org/downloads/macos/) or with `brew install python@3.13`.
- **Homebrew's `libomp`** for XGBoost. If Homebrew is installed, the script installs `libomp` for you. Without Homebrew, everything except XGBoost works.
- Internet access to `pypi.org`, and about 2 GB of free disk space.

## Files

| File | What it does |
|---|---|
| `requirements.txt` | The packages, with exact versions |
| `setup.sh` | Finds Python, creates `.venv`, installs the packages, registers the Jupyter kernel, runs the check |
| `check_env.py` | Checks every package's version, makes each one do real work, and confirms results are the same on every run |
| `logs/` | One log file per run |

## Options

```bash
./setup.sh --fresh                       # delete .venv and start clean
PYTHON=/opt/homebrew/bin/python3.13 ./setup.sh   # use a specific Python
.venv/bin/python check_env.py            # re-run only the check
```
