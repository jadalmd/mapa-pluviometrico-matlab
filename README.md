# mapa-pluviometrico-matlab

## Script Report: CEMADEN Monthly Rainfall Processing

This repository now includes the standalone script [cemaden_monthly_tolerance.py](cemaden_monthly_tolerance.py), created to run outside Jupyter and support reproducible rainfall processing workflows.

### Objective

Convert daily rainfall records into monthly totals using hydrological missing-data tolerance rules, enrich monthly outputs with station metadata, and export final results to MATLAB `.mat` format.

### Implemented Features

1. Daily to monthly aggregation with quality tolerance:
- Function: `aggregate_daily_to_monthly(df_daily, max_missing_days=3, min_completeness=0.90)`
- Required input columns: `gauge_code`, `datetime`, `rain_mm`
- Valid month criteria:
	- `missing_days <= max_missing_days`
	- `completeness >= min_completeness`

2. Merge with station metadata:
- Function: `merge_monthly_with_metadata(df_monthly_filtered, df_total_info)`
- Join key: `gauge_code`
- Join mode: `left` (keeps only stations present in `df_monthly_filtered`)
- Added metadata columns: `lat`, `long`, `city`, `state`, `network`

3. MATLAB export (`.mat`) for GUI usage:
- Function: `export_monthly_filtered_to_mat(df_monthly_filtered, output_mat_path='dados_hidro_br_mensal.mat')`
- Uses `scipy.io.savemat`
- Exports a MATLAB struct named `dados_hidro_br_mensal` with column-wise arrays for easy field access.

### Command-Line Usage

Generate monthly rainfall CSV from daily input:

```bash
python cemaden_monthly_tolerance.py daily_input.csv \
	--output-csv cemaden_monthly_tolerance.csv \
	--max-missing-days 3 \
	--min-completeness 0.90
```

### Programmatic Usage

```python
from cemaden_monthly_tolerance import (
		aggregate_daily_to_monthly,
		merge_monthly_with_metadata,
		export_monthly_filtered_to_mat,
)

# 1) Monthly aggregation with tolerance
df_monthly = aggregate_daily_to_monthly(df_cemaden_daily, 3, 0.90)

# 2) Example filtered monthly frame (expected columns: gauge_code, year, month, rain_mm)
# df_monthly_filtered = ...

# 3) Merge monthly values with station metadata
df_monthly_with_geo = merge_monthly_with_metadata(df_monthly_filtered, df_total_info)

# 4) Export filtered monthly table to MATLAB
export_monthly_filtered_to_mat(df_monthly_filtered, 'dados_hidro_br_mensal.mat')
```

### Dependencies

- `pandas`
- `scipy`

## Repository Organization

To reduce clutter and keep processing artifacts separated from source files:

1. Generated outputs are stored in [outputs](outputs).
2. MATLAB analysis scripts are stored in [scripts/matlab](scripts/matlab).
3. Python helper script folders are available in [scripts/python](scripts/python).

### New MATLAB Interactive Panel Script

Use [scripts/matlab/uniplu_station_panel.m](scripts/matlab/uniplu_station_panel.m) to:

1. Load `dados_hidro_br_mensal.mat`.
2. Select a state (`listdlg`).
3. Select a station (`city | gauge_code`).
4. Display three vertical panels (`tiledlayout(3,1)`):
	- data availability (month x year),
	- monthly hyetograph,
	- annual totals with Mann-Kendall/Sen trend summary via `ktaub`.