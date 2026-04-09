# UNIPLU-BR Hydroclimatic Processing and Visualization Toolkit

This repository contains an academic workflow for hydroclimatic analysis of Brazilian rainfall data from UNIPLU-BR. The workflow combines a Python preprocessing engine (quality control, temporal aggregation, and data packaging) with a MATLAB interactive dashboard (spatial and temporal interpretation).

## Project Overview

The project objective is to transform high-volume daily rainfall observations into hydrologically robust monthly and annual products, reducing data-availability bias and enabling transparent scientific interpretation.

## Prerequisites

### Software

1. Python 3.10 or newer
2. MATLAB

### Python libraries

1. pandas
2. scipy
3. pyarrow

Installation command:

```bash
python -m pip install pandas scipy pyarrow
```

## Architecture Flow

```mermaid
flowchart LR
    A[Raw Data] --> B[Python preprocessing (cemaden_monthly_tolerance.py applying 10% rule)]
    B --> C[Outputs (.mat and .csv)]
    C --> D[MATLAB interactive dashboard (uniplu_station_panel.m generating spatial maps, hyetographs, and MK trends)]
```

## Step-by-Step Recipe

### Step 1: Python preprocessing engine

Run the preprocessing pipeline from the repository root. This stage applies the strict hydrological filter (maximum 10% missing daily records per month, equivalent to minimum 90% completeness) before monthly aggregation.

```bash
c:/dev/jaidna/mapa-pluviometrico-matlab/.venv/Scripts/python.exe cemaden_monthly_tolerance.py --data-dir UNIPLU_BR-dados --states RS,SC --years 2023,2024 --output-csv outputs/df_monthly_filtered_real.csv --output-with-geo-csv outputs/df_monthly_filtered_with_geo_real.csv --output-mat outputs/dados_hidro_br_mensal_real.mat
```

Main products generated:

1. outputs/dados_hidro_br_mensal_real.mat
2. outputs/df_monthly_filtered_real.csv
3. outputs/df_monthly_filtered_with_geo_real.csv

### Step 2: MATLAB interactive dashboard

Run scripts/matlab/uniplu_station_panel.m in MATLAB.

1. Open MATLAB.
2. Set working directory to the project root.
3. Execute scripts/matlab/uniplu_station_panel.m.
4. Select analysis module, state/station scope, and time interval through dialog boxes.

## MATLAB Dashboard Outputs

The dashboard provides the following analysis products:

1. Spatial Interpolation Maps:
   Annual state-level rainfall maps generated using scatteredInterpolant and contourf.
2. Availability Matrices:
   Month-by-year visual diagnostics showing present versus missing observations.
3. Hyetographs:
   Annual precipitation signal with long-term mean and linear trendline.
4. Mann-Kendall / Sen's slope trend analysis:
   Non-parametric trend significance (p-value) and trend magnitude (Sen slope).

## Repository Structure

```text
mapa-pluviometrico-matlab/
|-- scripts/
|   |-- python/
|   `-- matlab/
|       `-- uniplu_station_panel.m
|-- outputs/
|-- UNIPLU_BR-dados/
|-- UNIPLU-BR/
|-- cemaden_monthly_tolerance.py
|-- pre_processamento.py
|-- pre-processamento.py
|-- mapapluviometria.m
`-- ktaub.m
```

## Scientific Notes

1. The 10% missing-data tolerance was adopted to prevent artificial dry-month detection caused by observational gaps.
2. Annual trend analysis should always be interpreted jointly by p-value and Sen's slope.
3. All outputs should be archived with run metadata (state filters, year range, command line, and script version) for reproducibility.