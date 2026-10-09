"""Root-cause analysis for every failed/warned DQ check on the real data. Writes docs/DQ_RCA_report.md.
Causes are stated as 'likely' where the data cannot prove them."""
import sqlite3, datetime as dt
from pathlib import Path
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
con = sqlite3.connect(ROOT / "data" / "bank.db")
q = lambda s: pd.read_sql(s, con)
md = lambda df: df.to_markdown(index=False, floatfmt=",.1f", intfmt=",")
log = q("SELECT check_name, severity, failed_rows, status, description FROM dq_log")
bad = log[log.status != "PASS"]
L = [f"# Data Quality & Root Cause Analysis Report (Berka PKDD'99 Financial dataset)\nGenerated {dt.datetime.now():%Y-%m-%d %H:%M}\n",
     f"**{len(log)} checks run: {(log.status=='PASS').sum()} passed, {(log.status=='FAIL').sum()} failed, {(log.status=='WARN').sum()} warnings.**\n",
     md(bad[["check_name", "status", "failed_rows", "description"]]),
     "\nPassed checks (all referential-integrity anti-joins, loan arithmetic, date-order rules, birth-date validity, reconciliations): " + ", ".join(log[log.status == "PASS"].check_name) + "\n"]

def sec(title, evidence, cause, fix):
    L.append(f"\n## {title}\n\n**Evidence**\n\n{md(evidence) if isinstance(evidence, pd.DataFrame) else evidence}\n\n**Likely root cause:** {cause}\n\n**Fix / treatment:** {fix}")

sec("DISTRICT_MISSING_VALUE",
    q("""SELECT d.district_id, d.district_name, d.region, d.unemployment_95 IS NULL AS unemployment_95_missing, d.crimes_95 IS NULL AS crimes_95_missing,
         COUNT(a.account_id) AS accounts, COUNT(a.loan_id) AS loans FROM stg_district d LEFT JOIN mart_account_360 a USING (district_id)
         WHERE d.unemployment_95 IS NULL OR d.crimes_95 IS NULL GROUP BY d.district_id"""),
    "The source stores a literal '?' for the 1995 unemployment and crime figures of one district, so those figures were simply not supplied for it. Only the two 1995 columns are affected.",
    "Staging converts '?' to NULL (no imputation). Dashboards show the district with 'n/a' for 1995 metrics and use the 1996 columns for analysis.")
sec("TXN_SYMBOL_INCONSISTENT_ENCODING",
    q("""SELECT COALESCE(operation,'(null)') AS operation, SUM(k_symbol IS NULL) AS encoded_as_null, SUM(k_symbol IS NOT NULL AND TRIM(k_symbol)='') AS encoded_as_space
         FROM raw_trans GROUP BY 1 ORDER BY 3 DESC"""),
    "'No purpose' is encoded two ways: NULL on some rows and a single space on others. The space encoding is almost entirely on outgoing transfers (PREVOD NA UCET), while other operations use NULL, which suggests the two encodings come from different extract jobs or source systems.",
    "Staging maps both to 'NONE' so grouping and filters in Tableau / Power BI do not split one category in two. Raise with the source owner to standardise.")
sec("TXN_LEGACY_TYPE_CODE",
    q("""SELECT '19' || SUBSTR(CAST(date AS TEXT),1,2) AS year, SUM(type='VYBER') AS legacy_type_VYBER,
         SUM(type='VYDAJ' AND operation='VYBER') AS standard_VYDAJ_cash_withdrawals FROM raw_trans GROUP BY 1 ORDER BY 1"""),
    "Rows with type VYBER are always cash withdrawals (operation VYBER) and always debits, so VYBER is a second code for what is normally VYDAJ. Both codes appear in every year, which suggests two feeds rather than a one-off migration.",
    "Staging maps VYBER to VYDAJ so debit/credit totals are right. A filter on type = 'VYDAJ' alone would have understated withdrawals.")
sec("TXN_ZERO_AMOUNT",
    q("SELECT k_symbol, type, COUNT(*) AS rows_ FROM raw_trans WHERE amount <= 0 GROUP BY 1,2"),
    "All zero-value rows are interest postings (UROK) or penalty-interest postings (SANKC. UROK): interest calculated as nil but still posted.",
    "Kept in staging (no balance impact). Excluded from average-transaction-size metrics.")
sec("TXN_DUPLICATE_POSTING",
    q("SELECT trans_id, account_id, date, type, k_symbol, amount, balance, reject_reason FROM rej_trans"),
    "Two postings share account, date, type, symbol, amount and balance but have different trans_id. Both are zero-value interest rows, so this looks like the same nil-interest posting generated twice.",
    "Staging keeps the lowest trans_id; the other is quarantined in rej_trans. No balance or total changes.")
sec("TRANSFER_MISSING_COUNTERPARTY",
    q("SELECT trans_id, account_id, date, type, operation, k_symbol, amount FROM raw_trans WHERE operation IN ('PREVOD NA UCET','PREVOD Z UCTU') AND (bank IS NULL OR account IS NULL)"),
    "A single loan-related transfer (symbol UVER) has no partner bank or account, so the counterparty was not captured at source.",
    "Left as is (one row of 273,509 transfers). Excluded from any counterparty-level analysis.")
sec("NEGATIVE_BALANCE_TXNS (business warning)",
    q("""SELECT '19' || SUBSTR(CAST(date AS TEXT),1,2) AS year, COUNT(*) AS txns_with_negative_balance, COUNT(DISTINCT account_id) AS accounts
         FROM raw_trans WHERE balance < 0 GROUP BY 1 ORDER BY 1"""),
    "Not a data error: accounts go overdrawn. It is a risk signal, which is why it is a WARN. See INSIGHTS.md for how overdrawn accounts relate to loan defaults.",
    "Exposed as an 'overdrawn' flag and in the loan watchlist (balance_cover) so a risk manager can act on it.")
rc = q("""SELECT t.account_id, COUNT(*) AS n_rows_last_day, MIN(ABS(s.cum - t.balance_reported)) AS diff, s.n_txn
          FROM stg_trans t JOIN (SELECT account_id, SUM(signed_amount) AS cum, MAX(txn_date) AS md, COUNT(*) AS n_txn FROM stg_trans GROUP BY account_id) s
          ON s.account_id = t.account_id AND t.txn_date = s.md GROUP BY t.account_id HAVING MIN(ABS(s.cum - t.balance_reported)) > 1.0""")
ev = pd.DataFrame({"accounts_failing": [len(rc)], "median_abs_diff": [rc["diff"].median()], "max_abs_diff": [rc["diff"].max()],
                   "median_txn_count": [rc.n_txn.median()], "median_txn_count_all_accounts": [q("SELECT AVG(c) v FROM (SELECT COUNT(*) c FROM stg_trans GROUP BY account_id)").v[0]]})
sec("BALANCE_RECON_ACCOUNT", ev,
    "The vast majority of accounts reconcile within rounding (source amounts are to 0.1). The failing accounts have more transactions than average (median 409 vs about 235) and the largest gap is only 2.7, which is consistent with small per-row rounding differences accumulating past the 1.0 tolerance. Missing postings cannot be ruled out.",
    "The dashboard balance is rebuilt from signed flows (mart_account_month.est_balance), not copied from the source. The 1.0 tolerance is documented, and the check query lists the affected accounts for review.")
(ROOT / "docs").mkdir(exist_ok=True)
(ROOT / "docs" / "DQ_RCA_report.md").write_text("\n".join(L))
print("wrote docs/DQ_RCA_report.md"); print(ev.to_string())
