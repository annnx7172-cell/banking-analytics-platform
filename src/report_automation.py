"""BAU report automation: builds the monthly banking summary (Excel workbook + HTML email body) from the mart views.
Power Automate (or cron / Task Scheduler) runs the pipeline then this script and emails the output; see docs/POWER_AUTOMATE_FLOW.md.
Data is as of Dec 1998 (the end of the Berka dataset)."""
import sqlite3, datetime as dt
from pathlib import Path
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
con = sqlite3.connect(ROOT / "data" / "bank.db")
out = ROOT / "exports"; out.mkdir(exist_ok=True)
q = lambda s: pd.read_sql(s, con)
v = lambda s: q(s).iloc[0, 0]

kpi = {
    "Data as of": "1998-12",
    "Accounts": int(v("SELECT COUNT(*) FROM mart_account_360")),
    "Total balance Dec-98 (reconstructed)": float(v("SELECT SUM(balance_dec98) FROM mart_account_360")),
    "Net cash flow 1998": float(v("SELECT SUM(net_flow) FROM mart_account_month WHERE month >= '1998-01'")),
    "Loans": int(v("SELECT COUNT(*) FROM stg_loan")),
    "Loan book (amount)": float(v("SELECT SUM(amount) FROM stg_loan")),
    "Bad loans % (by amount)": float(v("SELECT ROUND(100.0*SUM(CASE WHEN is_bad=1 THEN amount ELSE 0 END)/SUM(amount),1) FROM stg_loan")),
    "Accounts overdrawn in 1998": int(v("SELECT COUNT(*) FROM mart_account_360 WHERE negative_months_1998 > 0")),
    "DQ checks failed": int(v("SELECT COUNT(*) FROM dq_log WHERE status='FAIL'")),
    "DQ warnings": int(v("SELECT COUNT(*) FROM dq_log WHERE status='WARN'")),
}
stamp = dt.date.today().isoformat()
xlsx = out / f"banking_summary_{stamp}.xlsx"
with pd.ExcelWriter(xlsx) as xw:
    pd.DataFrame(kpi.items(), columns=["KPI", "Value"]).to_excel(xw, sheet_name="KPIs", index=False)
    q("SELECT * FROM vw_tier_summary").to_excel(xw, sheet_name="Tier summary", index=False)
    q("""SELECT region, COUNT(loan_id) AS loans, SUM(loan_amount) AS loan_amount, SUM(COALESCE(loan_is_bad,0)) AS bad_loans,
         ROUND(100.0*SUM(COALESCE(loan_is_bad,0))/COUNT(loan_id),1) AS bad_loan_pct
         FROM mart_account_360 WHERE loan_id IS NOT NULL GROUP BY region ORDER BY bad_loan_pct DESC""").to_excel(xw, sheet_name="Loans by region", index=False)
    q("SELECT * FROM vw_loan_watchlist ORDER BY amount DESC").to_excel(xw, sheet_name="Loan watchlist", index=False)
    q("SELECT * FROM dq_log").to_excel(xw, sheet_name="DQ status", index=False)

rows = "".join(f"<tr><td>{k}</td><td style='text-align:right'>{x:,.1f}</td></tr>" if isinstance(x, float)
               else f"<tr><td>{k}</td><td style='text-align:right'>{x:,}</td></tr>" if isinstance(x, int)
               else f"<tr><td>{k}</td><td style='text-align:right'>{x}</td></tr>" for k, x in kpi.items())
html = (f"<h3>Banking Monthly Summary ({stamp})</h3><table border='1' cellpadding='6' style='border-collapse:collapse'>{rows}</table>"
        "<p>Full workbook attached. DQ details: DQ_RCA_report.md.</p>")
(out / "email_body.html").write_text(html)
print("wrote", xlsx.name, "and email_body.html")
for k, x in kpi.items(): print(f"  {k}: {x}")
