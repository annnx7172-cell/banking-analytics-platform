"""Reruns the whole chain: pipeline -> root-cause report -> insights -> report workbook / email body."""
import subprocess, sys
from pathlib import Path
src = Path(__file__).resolve().parent
for s in ["pipeline.py", "dq_rca.py", "insights.py", "report_automation.py"]:
    print(f"== {s}"); subprocess.run([sys.executable, str(src / s)] + (sys.argv[1:] if s == "pipeline.py" else []), check=True)
print("Done. Dashboards read the CSVs in /exports.")
