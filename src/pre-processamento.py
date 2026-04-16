"""Pre-process UNIPLU rainfall data and export monthly results to MATLAB.

Pipeline:
1) Read daily and metadata CSV files.
2) Extract year/month from datetime.
3) Aggregate monthly rainfall with a strict 90% data-availability rule.
4) Left-merge with station metadata.
5) Export merged table to a MATLAB .mat file.
"""

from __future__ import annotations

import argparse
import calendar
from pathlib import Path

import pandas as pd
from scipy.io import savemat


def load_data(daily_csv: Path, info_csv: Path) -> tuple[pd.DataFrame, pd.DataFrame]:
	"""Load daily rainfall and metadata tables from CSV files."""
	df_cemaden_daily = pd.read_csv(daily_csv, parse_dates=["datetime"])
	df_total_info = pd.read_csv(info_csv)
	return df_cemaden_daily, df_total_info


def add_year_month(df_cemaden_daily: pd.DataFrame) -> pd.DataFrame:
	"""Add year and month columns extracted from datetime."""
	df = df_cemaden_daily.copy()
	df["year"] = df["datetime"].dt.year
	df["month"] = df["datetime"].dt.month
	return df


def _monthly_sum_with_tolerance(group: pd.DataFrame) -> float:
	"""Return monthly sum only when non-NaN coverage is at least 90%."""
	_, year, month = group.name
	year = int(year)
	month = int(month)
	total_days = calendar.monthrange(year, month)[1]

	valid_count = group["rain_mm"].notna().sum()
	min_required = 0.9 * total_days

	if valid_count < min_required:
		return float("nan")
	return group["rain_mm"].sum(skipna=True)


def aggregate_monthly(df_daily_with_dates: pd.DataFrame) -> pd.DataFrame:
	"""Aggregate to monthly rainfall with strict hydrological tolerance."""
	result = df_daily_with_dates.groupby(["gauge_code", "year", "month"]).apply(
		_monthly_sum_with_tolerance
	)
	df_monthly = result.rename("rain_mm").reset_index()
	return df_monthly[["gauge_code", "year", "month", "rain_mm"]]


def merge_with_metadata(
	df_monthly_filtered: pd.DataFrame,
	df_total_info: pd.DataFrame,
) -> pd.DataFrame:
	"""Left-join monthly rainfall with selected metadata fields."""
	metadata_cols = ["gauge_code", "lat", "long", "city", "state", "network"]
	df_info_unique = df_total_info[metadata_cols].drop_duplicates(subset=["gauge_code"])

	return df_monthly_filtered.merge(
		df_info_unique,
		on="gauge_code",
		how="left",
		validate="m:1",
	)


def _series_to_mat_array(series: pd.Series):
	"""Convert pandas series to MATLAB-friendly numpy arrays."""
	if pd.api.types.is_numeric_dtype(series):
		return pd.to_numeric(series, errors="coerce").to_numpy()
	if pd.api.types.is_datetime64_any_dtype(series):
		return series.dt.strftime("%Y-%m-%d %H:%M:%S").fillna("").to_numpy(dtype=object)
	if pd.api.types.is_bool_dtype(series):
		return series.fillna(False).astype("uint8").to_numpy()
	return series.astype("string").fillna("").to_numpy(dtype=object)


def export_mat(df_merged: pd.DataFrame, output_mat: Path) -> None:
	"""Export merged dataframe to .mat as a dictionary of column arrays."""
	mat_dict = {col: _series_to_mat_array(df_merged[col]) for col in df_merged.columns}
	savemat(output_mat, {"dados_hidro_br_mensal": mat_dict})


def _parse_args() -> argparse.Namespace:
	parser = argparse.ArgumentParser(description="Pre-process rainfall data and export MATLAB file.")
	parser.add_argument("--daily-csv", default="df_cemaden_daily.csv", help="Path to df_cemaden_daily.csv")
	parser.add_argument("--info-csv", default="df_total_info.csv", help="Path to df_total_info.csv")
	parser.add_argument(
		"--output-mat",
		default="dados_hidro_br_mensal.mat",
		help="Output MATLAB filename",
	)
	parser.add_argument(
		"--output-monthly-csv",
		default="df_monthly_filtered.csv",
		help="Optional export of monthly filtered dataframe",
	)
	parser.add_argument(
		"--output-merged-csv",
		default="df_monthly_filtered_merged.csv",
		help="Optional export of merged dataframe",
	)
	return parser.parse_args()


def main() -> None:
	args = _parse_args()

	df_cemaden_daily, df_total_info = load_data(Path(args.daily_csv), Path(args.info_csv))
	df_daily_with_dates = add_year_month(df_cemaden_daily)
	df_monthly_filtered = aggregate_monthly(df_daily_with_dates)
	df_monthly_merged = merge_with_metadata(df_monthly_filtered, df_total_info)

	df_monthly_filtered.to_csv(args.output_monthly_csv, index=False)
	df_monthly_merged.to_csv(args.output_merged_csv, index=False)
	export_mat(df_monthly_merged, Path(args.output_mat))

	print("Processamento concluido.")
	print(f"Monthly rows: {len(df_monthly_filtered)}")
	print(f"Merged rows: {len(df_monthly_merged)}")
	print(f"Saved: {args.output_monthly_csv}")
	print(f"Saved: {args.output_merged_csv}")
	print(f"Saved: {args.output_mat}")


if __name__ == "__main__":
	main()
