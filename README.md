# Workshop setup test

Sets up Python for the workshop without Anaconda, and checks that it works. Runs on a Mac, or on Windows through WSL (Ubuntu).

Open a terminal in your home folder and paste:

```bash
curl -fsSL https://github.com/am-consultingai/ds-workshop-setup/archive/refs/heads/main.tar.gz | tar xz && cd ds-workshop-setup-main && ./setup.sh
```

Or, with git:

```bash
git clone https://github.com/am-consultingai/ds-workshop-setup.git && cd ds-workshop-setup && ./setup.sh
```

It ends with **SUCCESS!!** or **FAILED at step: …**. Either way, the full log is in `logs/`.

## Where it installs

Everything goes into one environment at `~/.venvs/ds-workshop`, not into your system Python. It takes about 1.5 GB. It also registers a Jupyter kernel called **Python (ds-workshop)**.

Running the command again updates the same environment. It does not make a second copy.

## When the workshop project is ready

You will clone the project, link it to this environment once, and start Claude there:

```bash
git clone <project URL> && cd <project folder>
./link-env.sh
claude
```

`link-env.sh` makes `.venv` in the project point to `~/.venvs/ds-workshop`, so nothing is installed twice.

## What you need first

- **Python 3.12, 3.13 or 3.14.** Not Apple's built-in `/usr/bin/python3`, which is 3.9. Get it from [python.org](https://www.python.org/downloads/macos/) or with `brew install python@3.13`.
- **Homebrew's `libomp`** for XGBoost. If Homebrew is installed, the script installs `libomp` for you. Without Homebrew, everything except XGBoost works.
- Internet access to `pypi.org`, and about 2 GB of free disk space.

### On Windows (WSL)

- Use **Ubuntu 24.04 or newer**. It comes with Python 3.12.
- Ubuntu keeps the part of Python that creates virtual environments in a separate package. Install it first:
  ```bash
  sudo apt update && sudo apt install -y python3 python3-venv
  ```
  If your Python is 3.13 or 3.14, install `python3.13-venv` or `python3.14-venv` instead. The script tells you which one.
- `sudo` asks for your Linux password, the one you set up for WSL, not your Windows password.
- Run the setup in your Linux home folder (`cd ~`), not under `/mnt/c/`. The Windows drive is very slow from WSL.

## Files

| File | What it does |
|---|---|
| `requirements.txt` | The packages, with exact versions |
| `setup.sh` | Finds Python, creates `~/.venvs/ds-workshop`, installs the packages, registers the Jupyter kernel, runs the check |
| `check_env.py` | Checks every package's version, makes each one do real work, and confirms results are the same on every run |
| `logs/` | One log file per run |
| `template/link-env.sh` | Goes into the workshop project: links its `.venv` to this environment |

## Options

```bash
./setup.sh --fresh                       # delete the environment and start clean
PYTHON=/opt/homebrew/bin/python3.13 ./setup.sh   # use a specific Python
~/.venvs/ds-workshop/bin/python check_env.py     # re-run only the check
```
