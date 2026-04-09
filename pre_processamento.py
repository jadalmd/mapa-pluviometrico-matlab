"""UNIPLU-BR CSV pre-processing workflow for monthly hydroclimatic products.

Purpose:
    Process daily rainfall records from CSV sources and produce monthly totals
    that are hydrologically consistent for temporal analysis and MATLAB-based
    visualization.

Inputs:
    - Daily rainfall CSV with columns: gauge_code, datetime, rain_mm.
    - Station metadata CSV with columns including: gauge_code, lat, long,
      city, state, network.

Outputs:
    - Monthly filtered CSV (`df_monthly_filtered.csv` by default).
    - Monthly + metadata CSV (`df_monthly_filtered_merged.csv` by default).
    - MATLAB MAT file (`dados_hidro_br_mensal.mat` by default).

Hydrological criterion:
    Monthly totals are accepted only when at least 90% of expected daily
    observations are available. This strict 10% missing-data tolerance avoids
    false dry-month anomalies that would bias climatological interpretation.
"""

from __future__ import annotations

import argparse
import calendar
from pathlib import Path

import pandas as pd
from scipy.io import savemat


def load_data(daily_csv: Path, info_csv: Path) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Load daily rainfall and station metadata from CSV files.

    Args:
        daily_csv: Path to daily rainfall CSV.
        info_csv: Path to metadata CSV.

    Returns:
        Tuple (df_daily, df_info) where:
        - df_daily contains daily rainfall observations.
        - df_info contains station geospatial/context metadata.
    """
    df_daily = pd.read_csv(daily_csv, parse_dates=["datetime"])
    df_info = pd.read_csv(info_csv)
    return df_daily, df_info


def add_year_month(df_daily: pd.DataFrame) -> pd.DataFrame:
    """Derive calendar year/month fields from daily timestamps.

    Args:
        df_daily: Daily rainfall DataFrame with a datetime column.

    Returns:
        Copy of df_daily enriched with integer year and month columns.
    """
    df = df_daily.copy()
    df["year"] = df["datetime"].dt.year
    df["month"] = df["datetime"].dt.month
    return df


def _monthly_sum_with_tolerance(group: pd.DataFrame) -> float:
    """Compute monthly rainfall only when daily coverage is acceptable.

    Hydrological rule:
        For each gauge_code/year/month group, the expected number of daily
        observations is obtained from the Gregorian calendar. The monthly
        total is accepted only when available days >= 90% of expected days.

    Args:
        group: Daily records for a single (gauge_code, year, month) tuple.

    Returns:
        Monthly rainfall total when valid; NaN when quality threshold fails.
    """
    _, year, month = group.name
    total_days = calendar.monthrange(int(year), int(month))[1]

    valid_count = group["rain_mm"].notna().sum()
    min_required = 0.9 * total_days

    if valid_count < min_required:
        return float("nan")
    return group["rain_mm"].sum(skipna=True)


def aggregate_monthly(df_daily_with_dates: pd.DataFrame) -> pd.DataFrame:
    """Aggregate daily rainfall to monthly totals under strict QC.

    This function groups data by gauge_code/year/month and applies a strict
    10% missing-data tolerance threshold to avoid false dry-month anomalies in
    historical hydroclimatic series.

    Args:
        df_daily_with_dates: Daily rainfall DataFrame with year/month columns.

    Returns:
        DataFrame with columns: gauge_code, year, month, rain_mm.
    """
    result = df_daily_with_dates.groupby(["gauge_code", "year", "month"]).apply(
        _monthly_sum_with_tolerance
    )
    df_monthly = result.rename("rain_mm").reset_index()
    return df_monthly[["gauge_code", "year", "month", "rain_mm"]]


def merge_with_metadata(
    df_monthly_filtered: pd.DataFrame,
    df_info: pd.DataFrame,
) -> pd.DataFrame:
    """Merge monthly rainfall with station metadata.

    Args:
        df_monthly_filtered: Quality-controlled monthly rainfall table.
        df_info: Station metadata table.

    Returns:
        Left-joined DataFrame preserving all monthly rows and enriching each
        station with lat/long/city/state/network descriptors.
    """
    metadata_cols = ["gauge_code", "lat", "long", "city", "state", "network"]
    df_info_unique = df_info[metadata_cols].drop_duplicates(subset=["gauge_code"])

    return df_monthly_filtered.merge(
        df_info_unique,
        on="gauge_code",
        how="left",
        validate="m:1",
    )


def _series_to_mat_array(series: pd.Series):
    """Convert pandas Series to MATLAB-compatible arrays.

    Args:
        series: Input pandas Series.

    Returns:
        Numpy/object array that preserves numeric, datetime, boolean, or text
        semantics for MAT serialization.
    """
    if pd.api.types.is_numeric_dtype(series):
        return pd.to_numeric(series, errors="coerce").to_numpy()
    if pd.api.types.is_datetime64_any_dtype(series):
        return series.dt.strftime("%Y-%m-%d %H:%M:%S").fillna("").to_numpy(dtype=object)
    if pd.api.types.is_bool_dtype(series):
        return series.fillna(False).astype("uint8").to_numpy()
    return series.astype("string").fillna("").to_numpy(dtype=object)


def export_mat(df_merged: pd.DataFrame, output_mat: Path) -> None:
    """Export merged monthly table to MATLAB MAT file.

    Args:
        df_merged: Monthly rainfall table enriched with metadata.
        output_mat: Output path for MAT file.
    """
    mat_dict = {col: _series_to_mat_array(df_merged[col]) for col in df_merged.columns}
    savemat(output_mat, {"dados_hidro_br_mensal": mat_dict})


def _parse_args() -> argparse.Namespace:
    """Parse command-line arguments for CSV pre-processing mode."""
    parser = argparse.ArgumentParser(description="Pre-process rainfall data and export MATLAB file.")
    parser.add_argument("--daily-csv", default="df_cemaden_daily.csv", help="Path to daily rainfall CSV")
    parser.add_argument("--info-csv", default="df_total_info.csv", help="Path to station metadata CSV")
    parser.add_argument(
        "--output-mat",
        default="dados_hidro_br_mensal.mat",
        help="Output MATLAB filename",
    )
    parser.add_argument(
        "--output-monthly-csv",
        default="df_monthly_filtered.csv",
        help="Output path for filtered monthly CSV",
    )
    parser.add_argument(
        "--output-merged-csv",
        default="df_monthly_filtered_merged.csv",
        help="Output path for merged monthly+metadata CSV",
    )
    return parser.parse_args()


def main() -> None:
    """Run end-to-end CSV pre-processing and export output artifacts."""
    args = _parse_args()

    df_daily, df_info = load_data(Path(args.daily_csv), Path(args.info_csv))
    df_daily_with_dates = add_year_month(df_daily)

    # Monthly aggregation enforces the strict 10% missing-data threshold.
    df_monthly_filtered = aggregate_monthly(df_daily_with_dates)

    # Metadata merge keeps validated hydrological rows and appends coordinates.
    df_monthly_merged = merge_with_metadata(df_monthly_filtered, df_info)

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
