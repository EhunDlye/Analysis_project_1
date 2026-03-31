"""
数据加载与探索性数据分析 (EDA)
Data Loading and Exploratory Data Analysis (EDA)
"""

import os
import pandas as pd
import numpy as np


DATA_PATH = os.path.join(os.path.dirname(__file__), '..', 'data', 'sales_data.csv')


def load_data(filepath: str = DATA_PATH) -> pd.DataFrame:
    """Load the sales dataset from a CSV file."""
    df = pd.read_csv(filepath, parse_dates=['date'])
    return df


def basic_info(df: pd.DataFrame) -> None:
    """Print basic information about the dataset."""
    print("=" * 50)
    print("数据集基本信息 / Dataset Info")
    print("=" * 50)
    print(f"行数 / Rows:    {df.shape[0]}")
    print(f"列数 / Columns: {df.shape[1]}")
    print()
    print("列名及数据类型 / Column Types:")
    print(df.dtypes)
    print()
    print("缺失值统计 / Missing Values:")
    missing = df.isnull().sum()
    print(missing[missing > 0] if missing.any() else "  无缺失值 / No missing values")


def descriptive_stats(df: pd.DataFrame) -> pd.DataFrame:
    """Return descriptive statistics for numerical columns."""
    print()
    print("=" * 50)
    print("描述性统计 / Descriptive Statistics")
    print("=" * 50)
    stats = df.describe()
    print(stats)
    return stats


def category_analysis(df: pd.DataFrame) -> None:
    """Analyse categorical columns."""
    print()
    print("=" * 50)
    print("分类列分析 / Categorical Analysis")
    print("=" * 50)
    for col in ['region', 'product', 'category']:
        print(f"\n{col} 分布:")
        print(df[col].value_counts())


def time_series_summary(df: pd.DataFrame) -> pd.DataFrame:
    """Summarise sales and profit by month."""
    df = df.copy()
    df['month'] = df['date'].dt.to_period('M')
    monthly = (
        df.groupby('month')
        .agg(total_sales=('sales', 'sum'),
             total_profit=('profit', 'sum'),
             order_count=('date', 'count'))
        .reset_index()
    )
    print()
    print("=" * 50)
    print("月度销售汇总 / Monthly Sales Summary")
    print("=" * 50)
    print(monthly.to_string(index=False))
    return monthly


def region_product_pivot(df: pd.DataFrame) -> pd.DataFrame:
    """Return a pivot table of sales by region and product."""
    pivot = df.pivot_table(
        values='sales', index='region', columns='product', aggfunc='sum', fill_value=0
    )
    print()
    print("=" * 50)
    print("区域 × 产品 销售透视表 / Region × Product Sales Pivot")
    print("=" * 50)
    print(pivot)
    return pivot


def top_performers(df: pd.DataFrame, n: int = 5) -> pd.DataFrame:
    """Return the top-n records by profit."""
    top = df.nlargest(n, 'profit')[['date', 'region', 'product', 'sales', 'profit']]
    print()
    print(f"利润最高的 {n} 条记录 / Top {n} Records by Profit:")
    print(top.to_string(index=False))
    return top


if __name__ == '__main__':
    df = load_data()
    basic_info(df)
    descriptive_stats(df)
    category_analysis(df)
    time_series_summary(df)
    region_product_pivot(df)
    top_performers(df)
