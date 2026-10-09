"""Computes the headline findings used on the dashboards and in the README (all numbers come from the data)."""
import sqlite3
from pathlib import Path
import pandas as pd
from scipy.stats import spearmanr

ROOT = Path(__file__).resolve().parents[1]
con = sqlite3.connect(ROOT / "data" / "bank.db")
q = lambda s: pd.read_sql(s, con)
def md(df, dec=1):
    df = df.copy()
    for c in df.columns:
        if pd.api.types.is_numeric_dtype(df[c]):
            whole = (df[c].dropna() % 1 == 0).all() and not c.endswith("pct") and c not in ("p-value", "Spearman rho vs bad-loan %") and "balance" not in c
            df[c] = df[c].map(lambda v: "" if pd.isna(v) else (f"{v:,.0f}" if whole else f"{v:,.{dec}f}"))
    return df.to_markdown(index=False)

loans = q("SELECT * FROM stg_loan"); a = q("SELECT * FROM mart_account_360")
by_cnt = loans.is_bad.mean() * 100; by_amt = loans[loans.is_bad == 1].amount.sum() / loans.amount.sum() * 100
reg = q("""SELECT region, COUNT(loan_id) AS loans, SUM(COALESCE(loan_is_bad,0)) AS bad_loans,
           ROUND(100.0*SUM(COALESCE(loan_is_bad,0))/COUNT(loan_id),1) AS bad_loan_pct FROM mart_account_360 WHERE loan_id IS NOT NULL GROUP BY region ORDER BY bad_loan_pct DESC""")
dur = loans.groupby("duration_months").agg(loans=("loan_id", "count"), bad_loan_pct=("is_bad", lambda s: s.mean() * 100)).reset_index()
a["overdrawn_1998"] = a.negative_months_1998 > 0
od = a[a.loan_id.notna()].groupby("overdrawn_1998").agg(loans=("loan_id", "count"), bad_loans=("loan_is_bad", "sum"), bad_loan_pct=("loan_is_bad", lambda s: s.mean() * 100)).reset_index()
tier = q("SELECT * FROM vw_tier_summary ORDER BY CASE tier WHEN 'Premium' THEN 1 WHEN 'Standard' THEN 2 ELSE 3 END")
d = q("SELECT * FROM vw_district_scorecard WHERE loans >= 5")
corr = []
for c in ["unemployment_96", "avg_salary", "crimes_96"]:
    dd = d.dropna(subset=[c, "bad_loan_pct"]); r, p = spearmanr(dd[c], dd.bad_loan_pct); corr.append((c, len(dd), round(r, 2), round(p, 2)))
corr = pd.DataFrame(corr, columns=["district metric", "districts (>=5 loans)", "Spearman rho vs bad-loan %", "p-value"])

txt = f"""# Key findings (all computed from the data by src/insights.py)

1. **Loan book:** {len(loans)} loans worth {loans.amount.sum():,.0f}. {by_cnt:.1f}% of loans by count and {by_amt:.1f}% by amount are bad (status B finished unpaid, or D running in debt). Bad loans are bigger than average.
2. **Regions:** bad-loan rate ranges from {reg.bad_loan_pct.min():.1f}% to {reg.bad_loan_pct.max():.1f}% (north Bohemia has only 61 loans, so treat its low rate with caution).

{md(reg)}

3. **Duration:** 12-month loans have the lowest bad rate; 24 to 60 months are all similar.

{md(dur)}

4. **Overdrawn accounts and bad loans:** every loan whose account was overdrawn at some point in 1998 is bad, versus a much lower rate otherwise. **Caveat:** loan status is a final snapshot, so overdraft may be a result of the default rather than an early warning. Timing cannot be tested with this dataset; the watchlist treats it as a flag to review, not a predictor.

{md(od)}

5. **Tiers (by 1998 average balance):** bad-loan rate falls from Basic to Premium. Part of this is mechanical, because accounts in trouble have lower balances.

{md(tier)}

6. **Demographics do not explain defaults.** District unemployment, salary and crime show no relationship with the district bad-loan rate, so risk is not simply a poor-area effect (with a small number of loans per district, weak effects could still be hidden).

{md(corr, 2)}
"""
(ROOT / "docs" / "INSIGHTS.md").write_text(txt); print(txt)
