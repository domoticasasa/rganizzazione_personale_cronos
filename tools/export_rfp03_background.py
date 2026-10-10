"""Esporta Mod.RFP_03.xlsx in PDF di sfondo via Excel COM (Windows)."""
import sys
from pathlib import Path

xlsx = Path(r"c:\flutter_projects\organizzazione_personale_cronos - mod\assets\Mod.RFP_03.xlsx")
pdf = Path(r"c:\flutter_projects\organizzazione_personale_cronos - mod\assets\Mod.RFP_03_background.pdf")

try:
    import win32com.client  # type: ignore
except ImportError:
    print("pywin32 missing", file=sys.stderr)
    sys.exit(2)

excel = win32com.client.DispatchEx("Excel.Application")
excel.Visible = False
excel.DisplayAlerts = False
wb = None
try:
    wb = excel.Workbooks.Open(str(xlsx.resolve()))
    wb.ExportAsFixedFormat(0, str(pdf.resolve()))
    print(f"OK {pdf} size={pdf.stat().st_size}")
finally:
    if wb is not None:
        wb.Close(False)
    excel.Quit()
