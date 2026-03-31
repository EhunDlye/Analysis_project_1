"""
统计分析模块
Statistical Analysis Module
"""

import pandas as pd
import numpy as np
from scipy import stats as scipy_stats


def summary_by_group(df: pd.DataFrame, group_col: str, value_col: str = 'sales') -> pd.DataFrame:
    """
    Compute grouped summary statistics.

    Parameters
    ----------
    df        : DataFrame
    group_col : str – column to group by
    value_col : str – numerical column to aggregate
    """
    summary = (
        df.groupby(group_col)[value_col]
        .agg(['count', 'mean', 'std', 'min', 'max', 'sum'])
        .rename(columns={'count': '次数', 'mean': '均值', 'std': '标准差',
                         'min': '最小值', 'max': '最大值', 'sum': '总计'})
        .round(2)
    )
    print(f"\n按 {group_col} 汇总 ({value_col}) / Summary by {group_col} ({value_col}):")
    print(summary)
    return summary


def correlation_analysis(df: pd.DataFrame) -> pd.DataFrame:
    """Compute and print Pearson correlation matrix for numerical columns."""
    num_df = df.select_dtypes(include=[np.number])
    corr = num_df.corr().round(4)
    print("\n相关性矩阵 / Correlation Matrix:")
    print(corr)
    return corr


def anova_test(df: pd.DataFrame, group_col: str, value_col: str = 'sales') -> dict:
    """
    One-way ANOVA: test whether the mean of value_col differs across groups.

    Returns
    -------
    dict with 'f_statistic' and 'p_value'
    """
    groups = [group[value_col].values for _, group in df.groupby(group_col)]
    f_stat, p_value = scipy_stats.f_oneway(*groups)
    print(f"\n单因素方差分析 / One-Way ANOVA ({value_col} ~ {group_col}):")
    print(f"  F-statistic = {f_stat:.4f}")
    print(f"  p-value     = {p_value:.4f}")
    if p_value < 0.05:
        print("  结论: 各组均值存在显著差异 (p < 0.05) / Significant differences found.")
    else:
        print("  结论: 各组均值无显著差异 (p >= 0.05) / No significant differences found.")
    return {'f_statistic': f_stat, 'p_value': p_value}


def linear_regression(df: pd.DataFrame,
                       x_col: str = 'quantity',
                       y_col: str = 'sales') -> dict:
    """
    Simple linear regression using scipy.

    Returns
    -------
    dict with regression coefficients and R²
    """
    x = df[x_col].values
    y = df[y_col].values
    slope, intercept, r_value, p_value, std_err = scipy_stats.linregress(x, y)
    r_squared = r_value ** 2
    print(f"\n线性回归 / Linear Regression ({y_col} ~ {x_col}):")
    print(f"  截距 (intercept) = {intercept:.4f}")
    print(f"  斜率 (slope)     = {slope:.4f}")
    print(f"  R²               = {r_squared:.4f}")
    print(f"  p-value          = {p_value:.4f}")
    return {
        'slope': slope,
        'intercept': intercept,
        'r_squared': r_squared,
        'p_value': p_value,
        'std_err': std_err,
    }


def profit_rate_by_category(df: pd.DataFrame) -> pd.DataFrame:
    """Compute average profit margin per product category."""
    df = df.copy()
    df['profit_margin'] = df['profit'] / df['sales']
    result = df.groupby('category')['profit_margin'].mean().rename('avg_profit_margin').round(4)
    print("\n各类别平均利润率 / Avg Profit Margin by Category:")
    print(result)
    return result.reset_index()


def run_analysis(df: pd.DataFrame) -> None:
    """Run the full statistical analysis pipeline."""
    print("=" * 50)
    print("统计分析报告 / Statistical Analysis Report")
    print("=" * 50)
    summary_by_group(df, 'region', 'sales')
    summary_by_group(df, 'category', 'profit')
    correlation_analysis(df)
    anova_test(df, 'region', 'sales')
    anova_test(df, 'category', 'profit')
    linear_regression(df, 'quantity', 'sales')
    profit_rate_by_category(df)


if __name__ == '__main__':
    import os
    import sys
    sys.path.insert(0, os.path.dirname(__file__))
    from eda import load_data
    df = load_data()
    run_analysis(df)
