# Business Requirements (one page, written as if for a banking client)
**Stakeholders:** Head of Retail Banking, Head of Credit Risk, Data Governance.
| # | Stakeholder question | Deliverable | KPI |
|---|---|---|---|
| 1 | How are balances and cash flows trending, and which customer tiers drive them? | Dashboard page 1 | Total balance, monthly credits/debits, balance by tier and region |
| 2 | Where is the loan book deteriorating? | Dashboard page 2 | Bad-loan % by region, duration and tier; loan watchlist |
| 3 | Which accounts need attention now? | Dashboard page 2 | Overdrawn accounts, balance cover on bad loans |
| 4 | Do district demographics explain defaults? | Dashboard page 2 | Bad-loan % vs unemployment, salary, crime |
| 5 | Can I trust this month's numbers? | Dashboard page 3 + alert | DQ checks passed / failed / warned, with root cause |
| 6 | The report must reach us without manual work | Automated email | Monthly workbook + alert on FAIL |
**Assumptions:** bad loan = status B or D; tiers are quartiles of 1998 average balance; data is as of Dec 1998. **Out of scope:** real-time data, true Wealth / Wholesale segments.
