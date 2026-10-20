"""Checks that the workshop environment is ready.

Run it with the environment's Python:  .venv/bin/python check_env.py
Prints PASS or FAIL for each check and exits with 1 if anything failed.
Uses only the standard library until each package is tested, so it can
report a missing package instead of crashing on it.
"""
import importlib
import os
import re
import subprocess
import sys
import tempfile
import time
from importlib import metadata
from pathlib import Path

HERE = Path(__file__).resolve().parent
REQUIREMENTS = HERE / "requirements.txt"
KERNEL_NAME = "ds-workshop"
SUPPORTED_PYTHON = ((3, 12), (3, 14))

# Package name on PyPI -> name used in `import`
IMPORT_NAMES = {"scikit-learn": "sklearn", "PyYAML": "yaml"}

LIBOMP_FIX = (
    "XGBoost on macOS needs the OpenMP library from Homebrew.\n"
    "         Fix: brew install libomp   (then run setup.sh again)\n"
    "         No Homebrew? Install it from https://brew.sh, or ask IT."
)

results = []


def check(name):
    """Runs the decorated function as one check and records PASS or FAIL."""
    def wrap(fn):
        start = time.perf_counter()
        try:
            detail = fn() or ""
            results.append((True, name, detail))
            status = "PASS"
        except Exception as e:  # report every failure, never stop early
            detail = f"{type(e).__name__}: {e}"
            if name == "XGBoost" and "libomp" in str(e):
                detail += "\n         " + LIBOMP_FIX
            results.append((False, name, detail))
            status = "FAIL"
        ms = (time.perf_counter() - start) * 1000
        print(f"  {status}  {name:<32} {detail}  ({ms:.0f} ms)", flush=True)
        return fn
    return wrap


def read_requirements():
    pins = []
    for line in REQUIREMENTS.read_text().splitlines():
        line = line.split("#")[0].strip()
        if not line:
            continue
        m = re.fullmatch(r"([A-Za-z0-9_.\-]+)==([A-Za-z0-9_.\-]+)", line)
        if not m:
            raise ValueError(f"requirements.txt: expected 'name==version', got {line!r}")
        pins.append(m.groups())
    return pins


print(f"Workshop environment check  ·  Python {sys.version.split()[0]}  ·  {sys.executable}")
print()
print("1. Python")


@check("Python version")
def _():
    lo, hi = SUPPORTED_PYTHON
    v = sys.version_info[:2]
    if not lo <= v <= hi:
        raise RuntimeError(f"Python {v[0]}.{v[1]} found; need {lo[0]}.{lo[1]} to {hi[0]}.{hi[1]}")
    return f"{v[0]}.{v[1]}"


@check("Running in a virtual env")
def _():
    if sys.prefix == sys.base_prefix:
        raise RuntimeError("not inside a virtual environment; run with .venv/bin/python")
    return sys.prefix


print()
print("2. Packages: installed, right version, importable")
for dist, wanted in read_requirements():
    @check(dist)
    def _(dist=dist, wanted=wanted):
        found = metadata.version(dist)
        if found != wanted:
            raise RuntimeError(f"version {found} installed, requirements.txt pins {wanted}")
        importlib.import_module(IMPORT_NAMES.get(dist, dist))
        return found

print()
print("3. Each package does real work")


@check("NumPy maths")
def _():
    import numpy as np
    a = np.random.default_rng(0).normal(size=(200, 200))
    inv = np.linalg.inv(a @ a.T + np.eye(200))
    return f"200x200 inverse, max {abs(inv).max():.3f}"


@check("pandas tables and dates")
def _():
    import pandas as pd
    df = pd.DataFrame({"month": pd.date_range("2025-01-01", periods=12, freq="MS"),
                       "segment": ["SMB", "Enterprise"] * 6, "arr": range(12)})
    g = df.groupby("segment")["arr"].sum()
    assert g["SMB"] == 30 and g["Enterprise"] == 36
    return f"{len(df)} rows grouped"


@check("SciPy statistics")
def _():
    from scipy import stats
    p = stats.ttest_ind([1, 2, 3, 4, 5], [6, 7, 8, 9, 10]).pvalue
    assert p < 0.01
    return f"t-test p={p:.4f}"


@check("scikit-learn model")
def _():
    from sklearn.datasets import make_classification
    from sklearn.linear_model import LogisticRegression
    from sklearn.metrics import roc_auc_score
    from sklearn.model_selection import train_test_split
    X, y = make_classification(n_samples=2000, n_features=10, random_state=0)
    Xtr, Xte, ytr, yte = train_test_split(X, y, random_state=0)
    auc = roc_auc_score(yte, LogisticRegression(max_iter=1000).fit(Xtr, ytr).predict_proba(Xte)[:, 1])
    assert auc > 0.8, f"AUC {auc:.3f} is too low; the install may be broken"
    return f"logistic regression AUC {auc:.3f}"


@check("XGBoost")
def _():
    import xgboost as xgb
    from sklearn.datasets import make_classification
    X, y = make_classification(n_samples=2000, n_features=10, random_state=0)
    params = dict(n_estimators=50, max_depth=3, random_state=0, n_jobs=2)
    p1 = xgb.XGBClassifier(**params).fit(X, y).predict_proba(X)[:, 1]
    p2 = xgb.XGBClassifier(**params).fit(X, y).predict_proba(X)[:, 1]
    assert (p1 == p2).all(), "two runs with the same seed gave different results"
    return "trained twice, identical results"


@check("Same numbers every run")
def _():
    from sklearn.datasets import make_classification
    from sklearn.ensemble import RandomForestClassifier
    X, y = make_classification(n_samples=500, n_features=8, random_state=0)
    a = RandomForestClassifier(n_estimators=50, random_state=0).fit(X, y).predict_proba(X)[:, 1]
    b = RandomForestClassifier(n_estimators=50, random_state=0).fit(X, y).predict_proba(X)[:, 1]
    assert (a == b).all()
    return "random forest, seed 0, identical"


@check("matplotlib and seaborn charts")
def _():
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import seaborn as sns
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "chart.png"
        ax = sns.histplot(x=[1, 2, 2, 3, 3, 3])
        ax.figure.savefig(path)
        plt.close("all")
        size = path.stat().st_size
    assert size > 1000
    return f"PNG written ({size:,} bytes)"


@check("joblib save and load a model")
def _():
    import joblib
    from sklearn.linear_model import LogisticRegression
    m = LogisticRegression().fit([[0], [1], [2], [3]], [0, 0, 1, 1])
    with tempfile.TemporaryDirectory() as tmp:
        joblib.dump(m, Path(tmp) / "m.joblib")
        m2 = joblib.load(Path(tmp) / "m.joblib")
    assert (m.predict([[0], [3]]) == m2.predict([[0], [3]])).all()
    return "round trip OK"


@check("statsmodels regression table")
def _():
    import numpy as np
    import statsmodels.api as sm
    rng = np.random.default_rng(0)
    x = rng.normal(size=500)
    y = (rng.random(500) < 1 / (1 + np.exp(-(0.5 + 1.5 * x)))).astype(int)
    fit = sm.Logit(y, sm.add_constant(x)).fit(disp=0)
    assert fit.pvalues[1] < 0.001
    return f"logit slope {fit.params[1]:.2f}, p<0.001"


@check("Parquet and Excel files")
def _():
    import pandas as pd
    df = pd.DataFrame({"account_id": ["ACC-1", "ACC-2"], "region": ["NA", "EMEA"], "arr": [1000.0, 2500.0]})
    with tempfile.TemporaryDirectory() as tmp:
        df.to_parquet(Path(tmp) / "t.parquet")
        df.to_excel(Path(tmp) / "t.xlsx", index=False)
        back_pq = pd.read_parquet(Path(tmp) / "t.parquet")
        back_xl = pd.read_excel(Path(tmp) / "t.xlsx")
    assert back_pq.equals(df), "Parquet round trip changed the data"
    assert back_xl["arr"].tolist() == [1000.0, 2500.0]
    return "both round trips OK"


@check("DuckDB SQL on a DataFrame")
def _():
    import duckdb
    import pandas as pd
    accounts = pd.DataFrame({"segment": ["SMB", "SMB", "Enterprise"], "arr": [10, 20, 300]})
    out = duckdb.sql("SELECT segment, SUM(arr) AS arr FROM accounts GROUP BY segment ORDER BY segment").df()
    assert out["arr"].tolist() == [300, 30]
    return "GROUP BY returned the right totals"


@check("Plotly interactive chart")
def _():
    import plotly.express as px
    fig = px.bar(x=["SMB", "Enterprise"], y=[30, 300])
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "chart.html"
        fig.write_html(path, include_plotlyjs="cdn")
        size = path.stat().st_size
    assert size > 1000
    return f"HTML written ({size:,} bytes)"


@check("Widgets and progress bars")
def _():
    import ipywidgets
    from tqdm import tqdm
    ipywidgets.IntSlider(value=5, min=0, max=10)
    total = sum(tqdm(range(1000), disable=True))
    assert total == 499500
    return "slider created, tqdm OK"


@check("YAML config")
def _():
    import yaml
    cfg = yaml.safe_load("split: {method: time, gap_days: 90}\nseed: 0")
    assert cfg["split"]["gap_days"] == 90
    return "parsed"


print()
print("4. Jupyter")


@check("JupyterLab runs")
def _():
    jupyter = Path(sys.executable).parent / "jupyter"
    out = subprocess.run([str(jupyter), "lab", "--version"], capture_output=True, text=True, timeout=60)
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip() or "jupyter lab --version failed")
    return f"version {out.stdout.strip()}"


@check(f"Kernel '{KERNEL_NAME}' registered")
def _():
    from jupyter_client.kernelspec import KernelSpecManager
    specs = KernelSpecManager().find_kernel_specs()
    if KERNEL_NAME not in specs:
        raise RuntimeError(f"not found; run: .venv/bin/python -m ipykernel install --user --name {KERNEL_NAME}")
    return specs[KERNEL_NAME]


failed = [r for r in results if not r[0]]
print()
print(f"{len(results) - len(failed)} of {len(results)} checks passed.")
if failed:
    print("Failed: " + ", ".join(name for _, name, _ in failed))
sys.exit(1 if failed else 0)
