# Banking Analytics Platform on real bank data (Berka PKDD'99 Financial)
End-to-end BI and data-engineering project on a real anonymised Czech bank dataset (4,500 accounts, 5,369 clients, 682 loans, 1.06M transactions, 1993-1998):
raw -> staging -> marts (SQL joins, window functions, views) -> 24 data-quality checks with root-cause analysis -> Tableau and Power BI dashboards -> automated reporting.

**Data source:** [CTU Relational Dataset Repository, Financial](https://relational.fel.cvut.cz/dataset/Financial) (original: PKDD'99 Discovery Challenge). Put the 8 `.asc` files in `data/raw/` (or leave them in the parent folder).
**Be honest about the domain:** this is a retail bank. Customer tiers (quartiles of average balance) and the loan book stand in for Wealth and Wholesale segments, and the data ends in Dec 1998.

## Run it (about 30 seconds)
```
pip install pandas openpyxl tabulate scipy
python src/run_all.py            # pipeline, root-cause report, insights, report workbook
```
## What is in here
| Part | Where |
|---|---|
| SQL: staging, marts, 24 DQ checks | `sql/` (runs on SQLite) |
| Snowflake / SQL Server versions (untested, run them yourself) | `snowflake/`, `sqlserver/` |
| Root-cause report on the real data issues found | `docs/DQ_RCA_report.md` |
| Key findings | `docs/INSIGHTS.md` |
| Requirements, data dictionary, dashboard spec | `docs/` |
| Automation | `src/run_all.py`, `src/report_automation.py`, `docs/POWER_AUTOMATE_FLOW.md` |

## What the data quality layer found (real issues, not injected)
7 failed checks and 1 warning out of 24: a district with `?` placeholders, two encodings of "no purpose" (53,433 rows), a legacy withdrawal type code (16,666 rows), 14 zero-amount postings, a duplicate posting, one transfer with no counterparty, and 64 accounts whose balance does not reconcile within 1.0. 2,999 transactions leave accounts overdrawn (a business warning).

## What I would tell the Head of Credit Risk
15.1% of the loan book by amount is bad. All 29 loans on accounts overdrawn in 1998 are bad, so overdraft is the flag to review first (though it may be a result of default, not an early warning). District unemployment, salary and crime do not explain defaults. See `docs/INSIGHTS.md`.
