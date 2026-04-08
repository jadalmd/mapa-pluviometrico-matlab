"""Convert daily rainfall to monthly totals with hydrological missing-data tolerance.

Expected daily input columns:
- gauge_code
- datetime
- rain_mm
"""

from __future__ import annotations

import argparse

import pandas as pd
from scipy.io import savemat


REQUIRED_COLUMNS = {"gauge_code", "datetime", "rain_mm"}
MONTHLY_FILTERED_REQUIRED_COLUMNS = {"gauge_code", "year", "month", "rain_mm"}
METADATA_COLUMNS = ["gauge_code", "lat", "long", "city", "state", "network"]


def aggregate_daily_to_monthly(
    df_daily: pd.DataFrame,
    max_missing_days: int = 3,
    min_completeness: float = 0.90,
) -> pd.DataFrame:
    """Aggregate daily rainfall to monthly totals using tolerance rules.

    A month is valid when BOTH conditions are met:
    1) missing_days <= max_missing_days
    2) completeness >= min_completeness

    Invalid months are kept in the output, but `rain_mm_monthly` is set to NA.
    """
    missing_cols = REQUIRED_COLUMNS - set(df_daily.columns)
    if missing_cols:
        raise ValueError(f"Missing required columns: {sorted(missing_cols)}")

    if max_missing_days < 0:
        raise ValueError("max_missing_days must be >= 0")
    if not (0 <= min_completeness <= 1):
        raise ValueError("min_completeness must be between 0 and 1")

    df = df_daily.copy()
    df["datetime"] = pd.to_datetime(df["datetime"], errors="coerce")
    df["rain_mm"] = pd.to_numeric(df["rain_mm"], errors="coerce")

    # Remove records with invalid timestamp before period grouping.
    df = df.dropna(subset=["datetime"])

    monthly = (
        df.assign(month=df["datetime"].dt.to_period("M"))
        .groupby(["gauge_code", "month"], as_index=False)
        .agg(
            rain_mm_monthly_sum=("rain_mm", "sum"),
            n_days_with_data=("rain_mm", "count"),
        )
    )

    monthly["datetime"] = monthly["month"].dt.to_timestamp(how="start")
    monthly["n_days_expected"] = monthly["month"].dt.days_in_month
    monthly["missing_days"] = monthly["n_days_expected"] - monthly["n_days_with_data"]
    monthly["completeness"] = monthly["n_days_with_data"] / monthly["n_days_expected"]

    monthly["is_valid_month"] = (
        (monthly["missing_days"] <= max_missing_days)
        & (monthly["completeness"] >= min_completeness)
    )

    monthly["rain_mm_monthly"] = monthly["rain_mm_monthly_sum"].where(
        monthly["is_valid_month"], pd.NA
    )

    return (
        monthly[
            [
                "gauge_code",
                "datetime",
                "rain_mm_monthly",
                "n_days_expected",
                "n_days_with_data",
                "missing_days",
                "completeness",
                "is_valid_month",
            ]
        ]
        .sort_values(["gauge_code", "datetime"])
        .reset_index(drop=True)
    )


def merge_monthly_with_metadata(
    df_monthly_filtered: pd.DataFrame,
    df_total_info: pd.DataFrame,
) -> pd.DataFrame:
    """Left-join monthly rainfall with selected metadata columns.

    Keeps only rows from ``df_monthly_filtered`` and appends station attributes
    from ``df_total_info`` using ``gauge_code``.
    """
    missing_monthly = MONTHLY_FILTERED_REQUIRED_COLUMNS - set(df_monthly_filtered.columns)
    if missing_monthly:
        raise ValueError(
            f"df_monthly_filtered is missing columns: {sorted(missing_monthly)}"
        )

    missing_info = set(METADATA_COLUMNS) - set(df_total_info.columns)
    if missing_info:
        raise ValueError(f"df_total_info is missing columns: {sorted(missing_info)}")

    info = df_total_info[METADATA_COLUMNS].drop_duplicates(subset=["gauge_code"])

    merged = df_monthly_filtered.merge(
        info,
        on="gauge_code",
        how="left",
        validate="m:1",
    )

    return merged


def _matlab_column_array(series: pd.Series):
    """Convert a pandas Series into a MATLAB-friendly 1D array."""
    if pd.api.types.is_datetime64_any_dtype(series):
        # MATLAB reads this as a cell array of timestamp strings.
        return series.dt.strftime("%Y-%m-%d %H:%M:%S").fillna("").to_numpy(dtype=object)

    if pd.api.types.is_bool_dtype(series):
        # uint8 is robust across MATLAB versions for logical-like flags.
        return series.fillna(False).astype("uint8").to_numpy()

    if pd.api.types.is_numeric_dtype(series):
        return pd.to_numeric(series, errors="coerce").to_numpy()

    # Strings / mixed types are exported as MATLAB cell arrays of char vectors.
    return series.astype("string").fillna("").to_numpy(dtype=object)


def export_dataframe_to_mat(
    df: pd.DataFrame,
    output_mat_path: str = "dados_hidro_br_mensal.mat",
    matlab_struct_name: str = "dados_hidro_br_mensal",
) -> None:
    """Export a DataFrame to a .mat file as a MATLAB struct of column arrays."""
    mat_struct = {col: _matlab_column_array(df[col]) for col in df.columns}
    savemat(output_mat_path, {matlab_struct_name: mat_struct})


def export_monthly_filtered_to_mat(
    df_monthly_filtered: pd.DataFrame,
    output_mat_path: str = "dados_hidro_br_mensal.mat",
) -> None:
    """Export df_monthly_filtered to MATLAB .mat with column arrays."""
    required = {"gauge_code", "year", "month", "rain_mm"}
    missing = required - set(df_monthly_filtered.columns)
    if missing:
        raise ValueError(f"df_monthly_filtered is missing columns: {sorted(missing)}")

    export_dataframe_to_mat(
        df=df_monthly_filtered,
        output_mat_path=output_mat_path,
        matlab_struct_name="dados_hidro_br_mensal",
    )


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Aggregate daily rainfall CSV into monthly totals with tolerance filtering."
    )
    parser.add_argument("input_csv", help="Path to input CSV with daily rainfall.")
    parser.add_argument(
        "--output-csv",
        default="cemaden_monthly_tolerance.csv",
        help="Path to output CSV (default: cemaden_monthly_tolerance.csv).",
    )
    parser.add_argument(
        "--max-missing-days",
        type=int,
        default=3,
        help="Maximum missing daily values allowed per month (default: 3).",
    )
    parser.add_argument(
        "--min-completeness",
        type=float,
        default=0.90,
        help="Minimum monthly completeness ratio in [0, 1] (default: 0.90).",
    )
    return parser.parse_args()


def main() -> None:
    args = _parse_args()

    df_daily = pd.read_csv(args.input_csv)
    df_monthly = aggregate_daily_to_monthly(
        df_daily=df_daily,
        max_missing_days=args.max_missing_days,
        min_completeness=args.min_completeness,
    )

    df_monthly.to_csv(args.output_csv, index=False)

    valid_months = int(df_monthly["is_valid_month"].sum())
    total_months = int(len(df_monthly))
    print("Monthly aggregation finished with tolerance filtering.")
    print(f"Valid months: {valid_months} / {total_months}")
    print(f"Saved: {args.output_csv}")


if __name__ == "__main__":
    main()
