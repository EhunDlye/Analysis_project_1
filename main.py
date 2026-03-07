"""
主入口脚本 – 运行完整数据分析流程
Main entry script – runs the complete data analysis pipeline
"""

import os
import sys

# Allow running from repo root
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))

from eda import load_data, basic_info, descriptive_stats, category_analysis, time_series_summary, region_product_pivot, top_performers
from data_cleaning import clean_pipeline
from analysis import run_analysis
from visualization import generate_all_charts


def main() -> None:
    print("╔══════════════════════════════════════════╗")
    print("║  数据分析项目 / Data Analysis Project    ║")
    print("╚══════════════════════════════════════════╝")

    # 1. 加载数据
    print("\n【步骤 1】加载数据 / Step 1: Load Data")
    df_raw = load_data()

    # 2. 探索性数据分析
    print("\n【步骤 2】探索性数据分析 / Step 2: EDA")
    basic_info(df_raw)
    descriptive_stats(df_raw)
    category_analysis(df_raw)
    time_series_summary(df_raw)
    region_product_pivot(df_raw)
    top_performers(df_raw)

    # 3. 数据清洗
    print("\n【步骤 3】数据清洗 / Step 3: Data Cleaning")
    df_clean = clean_pipeline(df_raw)

    # 4. 统计分析
    print("\n【步骤 4】统计分析 / Step 4: Statistical Analysis")
    run_analysis(df_clean)

    # 5. 可视化
    print("\n【步骤 5】生成可视化图表 / Step 5: Visualization")
    generate_all_charts(df_clean)

    print("\n✓ 分析完成！图表保存于 results/ 目录。")
    print("✓ Analysis complete! Charts saved in the results/ directory.")


if __name__ == '__main__':
    main()
