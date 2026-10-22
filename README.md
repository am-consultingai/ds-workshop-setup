# Workshop setup

Sets up a Mac, or Windows through WSL (Ubuntu), for the data science workshop. No Anaconda.

Open a terminal in your home folder and paste:

```bash
curl -fsSL https://github.com/am-consultingai/ds-workshop-setup/archive/refs/heads/main.tar.gz | tar xz && cd ds-workshop-setup-main && ./setup.sh
```

It ends with **SUCCESS!!** or **FAILED at step: …**. Either way, the full log is in `logs/`.

## What it does

1. Checks the computer, the disk space and access to `pypi.org`.
2. Installs **Claude Code** if it's missing, and adds `~/.local/bin` to your PATH so `claude` starts from any folder.
3. Finds **Python 3.12, 3.13 or 3.14**, or installs it:
   - Mac: needs **Homebrew**. Without it, the script stops and prints Homebrew's install command. With it, the script runs `brew install python@3.13` itself, with no password.
   - Ubuntu/WSL: stops and asks you to run one `sudo apt install …` command.
4. On a Mac, installs Homebrew's `libomp`, which XGBoost needs.
5. Creates the environment at `~/.venvs/ds-workshop`.
6. Installs the packages in `requirements.txt`.
7. Registers the Jupyter kernel **Python (ds-workshop)**.
8. Runs `check_env.py`: 36 checks that every package is the right version and does real work.

The script never runs `sudo` itself. When a step needs your password, it stops and prints the exact command. Run it, then paste the setup command again. It picks up where it stopped.

Running the command again updates the same environment. It does not make a second copy.

## When the workshop project is ready

You will download the project, link it to this environment once, and start Claude there:

```bash
cd <project folder>
./link-env.sh
claude
```

`link-env.sh` makes `.venv` in the project point to `~/.venvs/ds-workshop`, so nothing is installed twice.

## Notes

- **Mac:** Homebrew is required, because XGBoost only finds `libomp` in Homebrew's folder. Installing Homebrew needs an admin account on the Mac.
- **Windows:** use Ubuntu 24.04 or newer, which comes with Python 3.12. `sudo` asks for your Linux password, the one you set up for WSL, not your Windows password. Run the setup in your Linux home folder (`cd ~`), not under `/mnt/c/`, which is very slow from WSL.
- About 2 GB of free disk space.

## Files

| File | What it does |
|---|---|
| `setup.sh` | Runs the steps above |
| `requirements.txt` | The packages, with exact versions |
| `check_env.py` | Checks every package's version, makes each one do real work, and confirms results are the same on every run |
| `logs/` | One log file per run |
| `template/link-env.sh` | Goes into the workshop project: links its `.venv` to this environment |

## Options

```bash
./setup.sh --fresh                               # delete the environment and start clean
PYTHON=/opt/homebrew/bin/python3.13 ./setup.sh   # use a specific Python
~/.venvs/ds-workshop/bin/python check_env.py     # re-run only the check
```
