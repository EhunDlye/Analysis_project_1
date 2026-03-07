"""
数据可视化模块
Data Visualization Module
"""

import os
import pandas as pd
import matplotlib
matplotlib.use('Agg')  # non-interactive backend for script usage
import matplotlib.pyplot as plt
import seaborn as sns

RESULTS_DIR = os.path.join(os.path.dirname(__file__), '..', 'results')
os.makedirs(RESULTS_DIR, exist_ok=True)

sns.set_theme(style='whitegrid', palette='muted')


def _save(fig: plt.Figure, filename: str) -> None:
    path = os.path.join(RESULTS_DIR, filename)
    fig.savefig(path, bbox_inches='tight', dpi=150)
    plt.close(fig)
    print(f"图表已保存 / Chart saved: {path}")


def plot_monthly_sales(df: pd.DataFrame) -> None:
    """Line chart: monthly total sales and profit."""
    df = df.copy()
    df['month'] = df['date'].dt.to_period('M').dt.to_timestamp()
    monthly = df.groupby('month').agg(sales=('sales', 'sum'), profit=('profit', 'sum')).reset_index()

    fig, ax = plt.subplots(figsize=(10, 5))
    ax.plot(monthly['month'], monthly['sales'], marker='o', label='Sales 销售额')
    ax.plot(monthly['month'], monthly['profit'], marker='s', linestyle='--', label='Profit 利润')
    ax.set_title('月度销售额与利润趋势 / Monthly Sales & Profit Trend')
    ax.set_xlabel('月份 / Month')
    ax.set_ylabel('金额 / Amount (¥)')
    ax.legend()
    fig.autofmt_xdate()
    _save(fig, 'monthly_sales_trend.png')


def plot_sales_by_region(df: pd.DataFrame) -> None:
    """Bar chart: total sales by region."""
    region_sales = df.groupby('region')['sales'].sum().sort_values(ascending=False).reset_index()

    fig, ax = plt.subplots(figsize=(7, 5))
    sns.barplot(data=region_sales, x='region', y='sales', ax=ax)
    ax.set_title('各区域销售总额 / Total Sales by Region')
    ax.set_xlabel('区域 / Region')
    ax.set_ylabel('销售额 / Sales (¥)')
    _save(fig, 'sales_by_region.png')


def plot_sales_by_category(df: pd.DataFrame) -> None:
    """Pie chart: sales share by product category."""
    cat_sales = df.groupby('category')['sales'].sum()

    fig, ax = plt.subplots(figsize=(6, 6))
    ax.pie(cat_sales, labels=cat_sales.index, autopct='%1.1f%%', startangle=140)
    ax.set_title('产品类别销售占比 / Sales Share by Category')
    _save(fig, 'sales_by_category.png')


def plot_profit_margin_distribution(df: pd.DataFrame) -> None:
    """Histogram: distribution of profit margin."""
    df = df.copy()
    df['profit_margin'] = df['profit'] / df['sales']

    fig, ax = plt.subplots(figsize=(7, 5))
    sns.histplot(df['profit_margin'], bins=20, kde=True, ax=ax)
    ax.set_title('利润率分布 / Profit Margin Distribution')
    ax.set_xlabel('利润率 / Profit Margin')
    ax.set_ylabel('频次 / Count')
    _save(fig, 'profit_margin_distribution.png')


def plot_correlation_heatmap(df: pd.DataFrame) -> None:
    """Heatmap: correlation among numerical features."""
    num_df = df.select_dtypes(include='number')

    fig, ax = plt.subplots(figsize=(7, 5))
    sns.heatmap(num_df.corr(), annot=True, fmt='.2f', cmap='coolwarm', ax=ax)
    ax.set_title('数值特征相关性热图 / Correlation Heatmap')
    _save(fig, 'correlation_heatmap.png')


def plot_product_sales_boxplot(df: pd.DataFrame) -> None:
    """Box plot: sales distribution per product."""
    fig, ax = plt.subplots(figsize=(9, 5))
    sns.boxplot(data=df, x='product', y='sales', ax=ax)
    ax.set_title('各产品销售额分布 / Sales Distribution by Product')
    ax.set_xlabel('产品 / Product')
    ax.set_ylabel('销售额 / Sales (¥)')
    ax.tick_params(axis='x', rotation=30)
    _save(fig, 'product_sales_boxplot.png')


def generate_all_charts(df: pd.DataFrame) -> None:
    """Generate all visualisation charts."""
    print("=== 生成可视化图表 / Generating Charts ===")
    plot_monthly_sales(df)
    plot_sales_by_region(df)
    plot_sales_by_category(df)
    plot_profit_margin_distribution(df)
    plot_correlation_heatmap(df)
    plot_product_sales_boxplot(df)
    print("所有图表已生成 / All charts generated.")


if __name__ == '__main__':
    import sys
    sys.path.insert(0, os.path.dirname(__file__))
    from eda import load_data
    df = load_data()
    generate_all_charts(df)
