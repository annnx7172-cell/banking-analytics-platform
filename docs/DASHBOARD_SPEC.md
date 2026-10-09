# Dashboard build spec (same KPIs in Tableau and Power BI)
Connect to the CSVs in `exports/` (or to Snowflake once loaded). Relationship: `mart_account_360.account_id` links to other account-level files.
**Page 1 - Balances and cash flow** (`vw_balance_trend_monthly`, `vw_cashflow_monthly`, `vw_tier_summary`): line of total balance by month split by tier; credits vs debits by month; table of tier summary. Filter: region.
**Page 2 - Credit risk** (`vw_loan_portfolio`, `vw_loan_watchlist`, `vw_district_scorecard`): bad-loan % by region (map or bars), by duration, by tier; watchlist table with balance_cover colour; scatter of district unemployment vs bad-loan % (it should show no pattern: say so in the title).
**Page 3 - Data quality** (`dq_log.csv`): count of PASS / FAIL / WARN, table of failing checks with failed_rows, text box with the root cause for the top 3 (from `DQ_RCA_report.md`).
**Power BI measures (DAX) to write:** `Bad Loan % = DIVIDE(SUM(vw_loan_portfolio[bad_amount]), SUM(vw_loan_portfolio[loan_amount]))`; `Balance MoM % = DIVIDE([Total Balance] - CALCULATE([Total Balance], DATEADD('Date'[Date], -1, MONTH)), CALCULATE([Total Balance], DATEADD('Date'[Date], -1, MONTH)))`.
Data note on every page: "Berka dataset, as of Dec 1998".
