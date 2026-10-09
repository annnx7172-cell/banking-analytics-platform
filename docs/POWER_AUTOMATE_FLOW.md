# Power Automate flow (build this yourself, about 30 min)
Needs a Microsoft 365 account with Power Automate (your college account may work; check).
**Flow 1: monthly report email**
1. Run `python src/run_all.py` on your laptop (or schedule it with cron / Task Scheduler); it writes the workbook and `email_body.html` into `exports/`, ideally a OneDrive/SharePoint synced folder.
2. Trigger: "When a file is created" in that folder, filter `banking_summary_*.xlsx`.
3. Get file content, then Send an email (V2): body = content of `email_body.html`, attachment = the workbook.
**Flow 2: DQ failure alert**
1. Trigger: "When a file is created or modified" for `exports/dq_log.csv`.
2. Parse the CSV (or use the Excel "List rows"), then Condition: any row with status = FAIL.
3. If yes, send an email or Teams message: "DQ checks failed, see DQ_RCA_report".
Screenshot both flows and one successful run into `docs/`. Only list Power Automate on your CV once a flow has actually run.
