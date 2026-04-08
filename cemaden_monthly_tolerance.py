"""Convert daily rainfall to monthly totals with hydrological missing-data tolerance.

Expected daily input columns:
- gauge_code
- datetime
- rain_mm
"""

from __future__ import annotations

import argparse
from pathlib import Path
import zipfile

import pandas as pd
from scipy.io import savemat


REQUIRED_COLUMNS = {"gauge_code", "datetime", "rain_mm"}
MONTHLY_FILTERED_REQUIRED_COLUMNS = {"gauge_code", "year", "month", "rain_mm"}
METADATA_COLUMNS = ["gauge_code", "lat", "long", "city", "state", "network"]


def read_uniplu_br(zip_path: Path, table: str = "table_data") -> pd.DataFrame:
    """Read a UNIPLU-BR parquet table from inside a ZIP file."""
    parquet_file = f"{table}.parquet"
    with zipfile.ZipFile(zip_path, "r") as zf:
        with zf.open(parquet_file) as file_obj:
            return pd.read_parquet(file_obj)


def load_uniplu_data(data_dir: Path, states: list[str], years: list[int]) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Load and concatenate UNIPLU rainfall and metadata tables from state/year ZIP files."""
    data_list: list[pd.DataFrame] = []
    info_list: list[pd.DataFrame] = []

    for state in states:
        for year in years:
            zip_path = data_dir / f"{state}_{year}.zip"
            if not zip_path.exists():
                print(f"Warning: file not found, skipping: {zip_path}")
                continue

            try:
                temp_data_df = read_uniplu_br(zip_path, "table_data")
                temp_info_df = read_uniplu_br(zip_path, "table_info")
            except KeyError as exc:
                print(f"Warning: missing parquet table in {zip_path}: {exc}")
                continue

            if not temp_data_df.empty:
                data_list.append(temp_data_df)
            if not temp_info_df.empty:
                info_list.append(temp_info_df)

    if not data_list:
        raise ValueError("No rainfall data loaded from provided data_dir/states/years.")
    if not info_list:
        raise ValueError("No metadata loaded from provided data_dir/states/years.")

    df_total_data = pd.concat(data_list, ignore_index=True)
    df_total_info = pd.concat(info_list, ignore_index=True).drop_duplicates(subset=["gauge_code"])
    return df_total_data, df_total_info


def build_cemaden_daily(df_total_data: pd.DataFrame, df_total_info: pd.DataFrame) -> pd.DataFrame:
    """Build CEMADEN daily rainfall totals from sub-daily records."""
    if "network" not in df_total_info.columns:
        raise ValueError("df_total_info must contain column: network")

    cemaden_codes = df_total_info[df_total_info["network"] == "CEMADEN"]["gauge_code"].unique()
    df_cemaden = df_total_data[df_total_data["gauge_code"].isin(cemaden_codes)].copy()

    if df_cemaden.empty:
        raise ValueError("No CEMADEN records found in loaded rainfall data.")

    df_cemaden["datetime"] = pd.to_datetime(df_cemaden["datetime"], errors="coerce")
    df_cemaden["rain_mm"] = pd.to_numeric(df_cemaden["rain_mm"], errors="coerce")
    df_cemaden = df_cemaden.dropna(subset=["datetime"])

    df_cemaden_daily = (
        df_cemaden.set_index("datetime")
        .groupby("gauge_code")["rain_mm"]
        .resample("24h", offset="12h", closed="right")
        .sum()
        .reset_index()
    )

    df_cemaden_daily["rain_mm"] = df_cemaden_daily.groupby("gauge_code")["rain_mm"].shift(1)
    df_cemaden_daily = df_cemaden_daily.dropna(subset=["rain_mm"]).reset_index(drop=True)
    return df_cemaden_daily


def build_monthly_filtered(df_daily: pd.DataFrame, max_missing_days: int, min_completeness: float) -> pd.DataFrame:
    """Create df_monthly_filtered with columns: gauge_code, year, month, rain_mm."""
    df_monthly = aggregate_daily_to_monthly(
        df_daily=df_daily,
        max_missing_days=max_missing_days,
        min_completeness=min_completeness,
    )

    df_monthly_filtered = (
        df_monthly[df_monthly["is_valid_month"]]
        .assign(
            year=lambda d: d["datetime"].dt.year,
            month=lambda d: d["datetime"].dt.month,
            rain_mm=lambda d: d["rain_mm_monthly"],
        )
        [["gauge_code", "year", "month", "rain_mm"]]
        .reset_index(drop=True)
    )
    return df_monthly_filtered


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
        description=(
            "Process CEMADEN rainfall to monthly totals with tolerance filtering. "
            "Works from daily CSV or directly from UNIPLU-BR ZIP/parquet files."
        )
    )
    parser.add_argument(
        "input_csv",
        nargs="?",
        help="Path to input CSV with daily rainfall (used when --data-dir is not provided).",
    )
    parser.add_argument(
        "--data-dir",
        default=None,
        help="Directory containing UNIPLU-BR ZIP files named like UF_YYYY.zip.",
    )
    parser.add_argument(
        "--states",
        default="RS,SC",
        help="Comma-separated state list for ZIP mode (default: RS,SC).",
    )
    parser.add_argument(
        "--years",
        default="2023,2024",
        help="Comma-separated year list for ZIP mode (default: 2023,2024).",
    )
    parser.add_argument(
        "--output-csv",
        default="df_monthly_filtered.csv",
        help="Path to output filtered monthly CSV (default: df_monthly_filtered.csv).",
    )
    parser.add_argument(
        "--output-with-geo-csv",
        default="df_monthly_filtered_with_geo.csv",
        help="Path to output merged monthly+metadata CSV (default: df_monthly_filtered_with_geo.csv).",
    )
    parser.add_argument(
        "--output-mat",
        default="dados_hidro_br_mensal.mat",
        help="Path to output MATLAB MAT file (default: dados_hidro_br_mensal.mat).",
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

    if args.data_dir:
        states = [state.strip().upper() for state in args.states.split(",") if state.strip()]
        years = [int(year.strip()) for year in args.years.split(",") if year.strip()]

        df_total_data, df_total_info = load_uniplu_data(Path(args.data_dir), states, years)
        df_cemaden_daily = build_cemaden_daily(df_total_data, df_total_info)
        df_monthly_filtered = build_monthly_filtered(
            df_cemaden_daily,
            max_missing_days=args.max_missing_days,
            min_completeness=args.min_completeness,
        )
        df_monthly_with_geo = merge_monthly_with_metadata(df_monthly_filtered, df_total_info)

        df_monthly_filtered.to_csv(args.output_csv, index=False)
        df_monthly_with_geo.to_csv(args.output_with_geo_csv, index=False)
        export_monthly_filtered_to_mat(df_monthly_filtered, args.output_mat)

        print("UNIPLU-BR ZIP pipeline completed.")
        print(f"Loaded rainfall rows: {len(df_total_data)}")
        print(f"Loaded stations: {len(df_total_info)}")
        print(f"Filtered monthly rows: {len(df_monthly_filtered)}")
        print(f"Saved: {args.output_csv}")
        print(f"Saved: {args.output_with_geo_csv}")
        print(f"Saved: {args.output_mat}")
        return

    if not args.input_csv:
        raise ValueError("Provide input_csv or use --data-dir for direct ZIP processing.")

    df_daily = pd.read_csv(args.input_csv)
    df_monthly_filtered = build_monthly_filtered(
        df_daily,
        max_missing_days=args.max_missing_days,
        min_completeness=args.min_completeness,
    )

    df_monthly_filtered.to_csv(args.output_csv, index=False)
    export_monthly_filtered_to_mat(df_monthly_filtered, args.output_mat)

    print("Daily CSV pipeline completed.")
    print(f"Filtered monthly rows: {len(df_monthly_filtered)}")
    print(f"Saved: {args.output_csv}")
    print(f"Saved: {args.output_mat}")


if __name__ == "__main__":
    main()
