# Analysis_project_1 – 数据分析项目

一个基于 Python 的销售数据分析代码仓库，涵盖数据加载、清洗、统计分析与可视化全流程。

> A Python-based sales data analysis repository covering the full pipeline:
> data loading → cleaning → statistical analysis → visualization.

---

## 项目结构 / Project Structure

```
Analysis_project_1/
├── data/
│   └── sales_data.csv          # 示例销售数据集 / Sample sales dataset
├── src/
│   ├── eda.py                  # 数据加载与探索性分析 / EDA
│   ├── data_cleaning.py        # 数据清洗 / Data cleaning
│   ├── analysis.py             # 统计分析 / Statistical analysis
│   └── visualization.py       # 数据可视化 / Visualization
├── tests/
│   └── test_analysis.py        # 单元测试 / Unit tests
├── results/                    # 生成的图表 / Generated charts
├── main.py                     # 一键运行全流程 / Run full pipeline
└── requirements.txt            # Python 依赖 / Dependencies
```

---

## 快速开始 / Quick Start

### 1. 安装依赖 / Install Dependencies

```bash
pip install -r requirements.txt
```

### 2. 运行完整分析 / Run Full Analysis

```bash
python main.py
```

分析完成后，所有图表将保存在 `results/` 目录。  
After the analysis, all charts will be saved in the `results/` directory.

### 3. 单独运行各模块 / Run Individual Modules

```bash
# 探索性数据分析 / EDA
python src/eda.py

# 数据清洗 / Data Cleaning
python src/data_cleaning.py

# 统计分析 / Statistical Analysis
python src/analysis.py

# 可视化 / Visualization
python src/visualization.py
```

---

## 功能说明 / Features

| 模块 Module | 功能 Functionality |
|---|---|
| `eda.py` | 数据加载、基本信息、描述性统计、分类分析、月度汇总、透视表 |
| `data_cleaning.py` | 去重、缺失值处理、IQR 离群值过滤、衍生列生成 |
| `analysis.py` | 分组统计、相关性分析、单因素 ANOVA、线性回归、利润率分析 |
| `visualization.py` | 月度趋势折线图、区域销售柱状图、类别占比饼图、利润率直方图、相关性热图、产品箱线图 |

---

## 数据集 / Dataset

`data/sales_data.csv` 包含 2024 年 1–6 月的模拟销售记录，字段如下：

| 字段 Field | 说明 Description |
|---|---|
| `date` | 销售日期 / Sale date |
| `region` | 销售区域 (East/West/North/South) |
| `product` | 产品名称 / Product name |
| `category` | 产品类别 (Electronics/Furniture/Stationery) |
| `sales` | 销售额 / Revenue (¥) |
| `quantity` | 销售数量 / Units sold |
| `discount` | 折扣率 / Discount rate |
| `profit` | 利润 / Profit (¥) |

---

## 测试 / Tests

```bash
python -m pytest tests/ -v
```

---

## 依赖 / Dependencies

- pandas ≥ 2.0
- numpy ≥ 1.24
- matplotlib ≥ 3.7
- seaborn ≥ 0.12
- scikit-learn ≥ 1.3
- scipy (included with scikit-learn)
