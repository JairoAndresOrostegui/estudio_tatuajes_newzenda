"""Read-only structural audit. Never emits customer/artist records or cell contents.
Usage: python scripts/inspect_excel.py PATH.xlsx > artifacts/excel-audit.json
Requires: pip install openpyxl
"""
import json
import sys
from openpyxl import load_workbook

workbook = load_workbook(sys.argv[1], read_only=True, data_only=False)
result = []
for sheet in workbook:
    count = formulas = errors = 0
    for row in sheet:
        if any(cell.value is not None for cell in row):
            count += 1
        for cell in row:
            formulas += cell.data_type == 'f'
            errors += cell.data_type == 'e' or (cell.data_type == 'f' and '#REF!' in str(cell.value))
    result.append({'sheet': sheet.title, 'nonEmptyRows': count,
                   'formulaCells': formulas, 'errorCells': errors})
print(json.dumps(result, ensure_ascii=False, indent=2))
