# Plan to finish by Sunday 11 Oct (registration closes). Aim to submit Sunday morning, not in the last hour.
The data and Python/SQL core are already done and tested. What remains is the tool work only you can do.

## Friday evening (about 3 hours)
1. (20 min) Put the folder next to your .asc files, run `python src/run_all.py`, check `exports/` has CSVs. Read `docs/INSIGHTS.md` and `docs/DQ_RCA_report.md` so you can explain them.
2. (2 hrs) Snowflake trial: run `snowflake/setup_and_load.sql`, load the 8 files, build `STG_TRANS` and `STG_LOAN`, run two mart queries. Screenshot row counts.
3. (30 min) Create the GitHub repo and push.

## Saturday (about 6 hours)
1. (3 hrs) Tableau Public (works on Mac): build the 3 pages in `docs/DASHBOARD_SPEC.md` from `exports/`. Publish and save the link.
2. (2 hrs) Power BI (Windows only: use a lab PC, a VM, or Power BI Service in the browser): the same 3 pages, plus the 2 DAX measures.
3. (45 min) Power Automate: the two flows in `docs/POWER_AUTOMATE_FLOW.md`.

## Sunday morning
1. (60 min) SQL Server / Azure SQL: run `sqlserver/usp_pipeline.sql` after loading the raw tables. If it will not run, remove SQL Server from your CV.
2. (30 min) Update the README with dashboard links and screenshots.
3. Finalise the CV: delete every tool you did not actually use. Submit.

## If time runs short, cut in this order
Power Automate, then SQL Server, then the Power BI third page. Keep Snowflake, Tableau and the data-quality story.
