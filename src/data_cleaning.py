"""
数据清洗模块
Data Cleaning Module
"""

import pandas as pd
import numpy as np


def remove_duplicates(df: pd.DataFrame) -> pd.DataFrame:
    """Remove duplicate rows and report the count removed."""
    before = len(df)
    df = df.drop_duplicates()
    removed = before - len(df)
    print(f"重复行已删除 / Duplicates removed: {removed}")
    return df


def handle_missing_values(df: pd.DataFrame, strategy: str = 'drop') -> pd.DataFrame:
    """
    Handle missing values.

    Parameters
    ----------
    df : DataFrame
    strategy : str
        'drop'  – drop rows with any NaN
        'mean'  – fill numerical NaNs with column mean
        'median'– fill numerical NaNs with column median
    """
    if strategy not in ('drop', 'mean', 'median'):
        raise ValueError(f"Unknown strategy: {strategy}")

    missing_before = df.isnull().sum().sum()
    if missing_before == 0:
        print("无缺失值，无需处理 / No missing values found.")
        return df

    if strategy == 'drop':
        df = df.dropna()
    elif strategy in ('mean', 'median'):
        num_cols = df.select_dtypes(include=[np.number]).columns
        for col in num_cols:
            fill_value = df[col].mean() if strategy == 'mean' else df[col].median()
            df[col] = df[col].fillna(fill_value)

    missing_after = df.isnull().sum().sum()
    print(f"缺失值处理 / Missing values: {missing_before} → {missing_after}")
    return df


def remove_outliers_iqr(df: pd.DataFrame, column: str) -> pd.DataFrame:
    """
    Remove outliers from a numerical column using the IQR method.

    Parameters
    ----------
    df     : DataFrame
    column : str – column name to filter
    """
    q1 = df[column].quantile(0.25)
    q3 = df[column].quantile(0.75)
    iqr = q3 - q1
    lower = q1 - 1.5 * iqr
    upper = q3 + 1.5 * iqr
    before = len(df)
    df = df[(df[column] >= lower) & (df[column] <= upper)]
    removed = before - len(df)
    print(f"离群值已删除 ({column}) / Outliers removed ({column}): {removed}")
    return df


def add_derived_columns(df: pd.DataFrame) -> pd.DataFrame:
    """Add useful derived columns to the DataFrame."""
    df = df.copy()
    df['profit_margin'] = (df['profit'] / df['sales']).round(4)
    df['net_sales'] = (df['sales'] * (1 - df['discount'])).round(2)
    df['month'] = df['date'].dt.month
    df['quarter'] = df['date'].dt.quarter
    df['weekday'] = df['date'].dt.day_name()
    print("衍生列已添加 / Derived columns added: profit_margin, net_sales, month, quarter, weekday")
    return df


def clean_pipeline(df: pd.DataFrame) -> pd.DataFrame:
    """Run the full cleaning pipeline and return the cleaned DataFrame."""
    print("=== 数据清洗流程 / Data Cleaning Pipeline ===")
    df = remove_duplicates(df)
    df = handle_missing_values(df, strategy='mean')
    df = remove_outliers_iqr(df, 'sales')
    df = add_derived_columns(df)
    print(f"清洗完成，剩余记录 / Cleaning done, records remaining: {len(df)}")
    return df


if __name__ == '__main__':
    import os
    import sys
    sys.path.insert(0, os.path.dirname(__file__))
    from eda import load_data
    df = load_data()
    df_clean = clean_pipeline(df)
    print(df_clean.head())
