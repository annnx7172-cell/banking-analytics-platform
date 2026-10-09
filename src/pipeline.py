"""End-to-end pipeline on the real Berka (PKDD'99 Financial) dataset:
raw .asc files -> raw tables -> staging -> marts -> data-quality checks -> CSV exports for Tableau / Power BI.
Run:  python src/pipeline.py [path_to_folder_with_.asc_files]
SQL is SQLite here; Snowflake / SQL Server versions are in /snowflake and /sqlserver."""
import sqlite3, sys, logging, datetime as dt
from pathlib import Path
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "data" / "bank.db"
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("pipeline")
TABLES = {"account": "account", "client": "client", "disp": "disp", "district": "district",
          "loan": "loan", "card": "card", "order": "order", "trans": "trans"}

def find_data_dir():
    if len(sys.argv) > 1: return Path(sys.argv[1])
    for p in [ROOT / "data" / "raw", ROOT / "data", ROOT.parent, Path.cwd()]:
        if (p / "trans.asc").exists(): return p
    raise SystemExit("Put the Berka .asc files in data/raw (or pass the folder path as an argument).")

def load_raw(con, d):
    for t in TABLES:
        df = pd.read_csv(d / f"{t}.asc", sep=";", low_memory=False)
        df.to_sql(f"raw_{t}", con, if_exists="replace", index=False, chunksize=100_000)
        log.info("loaded raw_%s: %s rows", t, f"{len(df):,}")
    con.execute("CREATE INDEX idx_raw_trans_acct ON raw_trans (account_id)")
    con.execute("CREATE INDEX idx_raw_disp_acct ON raw_disp (account_id)")
    con.commit()

def run_sql_file(con, p):
    log.info("running %s", Path(p).name); con.executescript(Path(p).read_text())

def run_dq(con):
    con.execute("DROP TABLE IF EXISTS dq_log")
    con.execute("CREATE TABLE dq_log (run_ts TEXT, check_name TEXT, layer TEXT, severity TEXT, failed_rows INT, status TEXT, description TEXT)")
    ts = dt.datetime.now().isoformat(timespec="seconds")
    for stmt in (ROOT / "sql" / "03_dq_checks.sql").read_text().split(";\n"):
        body = "\n".join(l for l in stmt.splitlines() if not l.strip().startswith("--")).strip().rstrip(";")
        if not body: continue
        name, layer, sev, n, desc = con.execute(body).fetchone()
        status = "PASS" if n == 0 else sev
        con.execute("INSERT INTO dq_log VALUES (?,?,?,?,?,?,?)", (ts, name, layer, sev, n, status, desc))
        log.info("DQ %-34s %-5s failed_rows=%-8s %s", name, layer, f"{n:,}", status)
    con.commit()

def export(con):
    out = ROOT / "exports"; out.mkdir(exist_ok=True)
    views = [r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='view'")]
    for v in views: pd.read_sql(f"SELECT * FROM {v}", con).to_csv(out / f"{v}.csv", index=False)
    for t in ["dq_log", "mart_account_360", "stg_district"]:
        pd.read_sql(f"SELECT * FROM {t}", con).to_csv(out / f"{t}.csv", index=False)
    log.info("exported %d views + dq_log + mart_account_360 + stg_district to /exports", len(views))

def main():
    d = find_data_dir(); DB.parent.mkdir(exist_ok=True)
    if DB.exists(): DB.unlink()
    con = sqlite3.connect(DB)
    load_raw(con, d)
    for f in ["01_staging.sql", "02_marts.sql"]: run_sql_file(con, ROOT / "sql" / f)
    run_dq(con); export(con); con.close()

if __name__ == "__main__":
    main()
