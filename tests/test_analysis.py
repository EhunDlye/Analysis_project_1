"""
单元测试
Unit Tests for the data analysis modules
"""

import os
import sys
import unittest
import pandas as pd
import numpy as np

# Make src importable
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from eda import load_data, descriptive_stats, time_series_summary, region_product_pivot, top_performers
from data_cleaning import (remove_duplicates, handle_missing_values,
                            remove_outliers_iqr, add_derived_columns, clean_pipeline)
from analysis import (summary_by_group, correlation_analysis,
                      anova_test, linear_regression, profit_rate_by_category)


# ── Fixtures ──────────────────────────────────────────────────────────────────

def make_sample_df() -> pd.DataFrame:
    """Return a small deterministic DataFrame for testing."""
    data = {
        'date': pd.to_datetime(['2024-01-01', '2024-01-15', '2024-02-01',
                                 '2024-02-15', '2024-03-01']),
        'region': ['East', 'West', 'East', 'North', 'West'],
        'product': ['Widget A', 'Widget B', 'Gadget X', 'Widget A', 'Widget B'],
        'category': ['Electronics', 'Electronics', 'Electronics', 'Electronics', 'Electronics'],
        'sales': [1200.0, 850.0, 2300.0, 1100.0, 950.0],
        'quantity': [10, 7, 15, 9, 8],
        'discount': [0.05, 0.10, 0.00, 0.05, 0.10],
        'profit': [240.0, 127.5, 460.0, 198.0, 142.5],
    }
    return pd.DataFrame(data)


# ── EDA tests ─────────────────────────────────────────────────────────────────

class TestLoadData(unittest.TestCase):
    def test_load_returns_dataframe(self):
        df = load_data()
        self.assertIsInstance(df, pd.DataFrame)

    def test_expected_columns(self):
        df = load_data()
        expected = {'date', 'region', 'product', 'category', 'sales', 'quantity', 'discount', 'profit'}
        self.assertTrue(expected.issubset(set(df.columns)))

    def test_date_column_is_datetime(self):
        df = load_data()
        self.assertTrue(pd.api.types.is_datetime64_any_dtype(df['date']))

    def test_no_negative_sales(self):
        df = load_data()
        self.assertTrue((df['sales'] >= 0).all())


class TestDescriptiveStats(unittest.TestCase):
    def test_returns_dataframe(self):
        df = make_sample_df()
        result = descriptive_stats(df)
        self.assertIsInstance(result, pd.DataFrame)

    def test_contains_mean_and_std(self):
        df = make_sample_df()
        result = descriptive_stats(df)
        self.assertIn('mean', result.index)
        self.assertIn('std', result.index)


class TestTimeSeries(unittest.TestCase):
    def test_monthly_summary_shape(self):
        df = make_sample_df()
        monthly = time_series_summary(df)
        self.assertIn('total_sales', monthly.columns)
        self.assertEqual(len(monthly), 3)  # Jan, Feb, Mar


class TestRegionProductPivot(unittest.TestCase):
    def test_pivot_index_is_region(self):
        df = make_sample_df()
        pivot = region_product_pivot(df)
        self.assertEqual(pivot.index.name, 'region')


class TestTopPerformers(unittest.TestCase):
    def test_returns_n_rows(self):
        df = make_sample_df()
        top = top_performers(df, n=3)
        self.assertEqual(len(top), 3)

    def test_sorted_descending(self):
        df = make_sample_df()
        top = top_performers(df, n=5)
        self.assertEqual(top.iloc[0]['profit'], df['profit'].max())


# ── Data Cleaning tests ────────────────────────────────────────────────────────

class TestRemoveDuplicates(unittest.TestCase):
    def test_removes_duplicates(self):
        df = make_sample_df()
        df_dup = pd.concat([df, df.iloc[:2]], ignore_index=True)
        df_clean = remove_duplicates(df_dup)
        self.assertEqual(len(df_clean), len(df))

    def test_no_duplicates_unchanged(self):
        df = make_sample_df()
        df_clean = remove_duplicates(df)
        self.assertEqual(len(df_clean), len(df))


class TestHandleMissingValues(unittest.TestCase):
    def _df_with_nan(self):
        df = make_sample_df()
        df.loc[0, 'sales'] = np.nan
        return df

    def test_drop_strategy(self):
        df = self._df_with_nan()
        df_clean = handle_missing_values(df, strategy='drop')
        self.assertEqual(df_clean.isnull().sum().sum(), 0)
        self.assertEqual(len(df_clean), len(df) - 1)

    def test_mean_strategy(self):
        df = self._df_with_nan()
        df_clean = handle_missing_values(df, strategy='mean')
        self.assertEqual(df_clean['sales'].isnull().sum(), 0)

    def test_no_missing_no_change(self):
        df = make_sample_df()
        df_clean = handle_missing_values(df, strategy='drop')
        self.assertEqual(len(df_clean), len(df))

    def test_invalid_strategy_raises(self):
        df = make_sample_df()
        with self.assertRaises(ValueError):
            handle_missing_values(df, strategy='unknown')


class TestRemoveOutliersIQR(unittest.TestCase):
    def test_removes_extreme_outlier(self):
        df = make_sample_df()
        df.loc[len(df)] = df.iloc[0].copy()
        df.at[len(df) - 1, 'sales'] = 1_000_000  # extreme outlier
        df_clean = remove_outliers_iqr(df, 'sales')
        self.assertFalse((df_clean['sales'] > 100_000).any())


class TestAddDerivedColumns(unittest.TestCase):
    def test_columns_added(self):
        df = make_sample_df()
        df_aug = add_derived_columns(df)
        for col in ['profit_margin', 'net_sales', 'month', 'quarter', 'weekday']:
            self.assertIn(col, df_aug.columns)

    def test_profit_margin_calculation(self):
        df = make_sample_df()
        df_aug = add_derived_columns(df)
        expected = (df['profit'] / df['sales']).round(4)
        pd.testing.assert_series_equal(df_aug['profit_margin'], expected, check_names=False)


class TestCleanPipeline(unittest.TestCase):
    def test_returns_dataframe(self):
        df = make_sample_df()
        df_clean = clean_pipeline(df)
        self.assertIsInstance(df_clean, pd.DataFrame)

    def test_has_derived_columns(self):
        df = make_sample_df()
        df_clean = clean_pipeline(df)
        self.assertIn('profit_margin', df_clean.columns)


# ── Analysis tests ─────────────────────────────────────────────────────────────

class TestSummaryByGroup(unittest.TestCase):
    def test_returns_dataframe(self):
        df = make_sample_df()
        result = summary_by_group(df, 'region', 'sales')
        self.assertIsInstance(result, pd.DataFrame)

    def test_groups_correct(self):
        df = make_sample_df()
        result = summary_by_group(df, 'region', 'sales')
        self.assertEqual(set(result.index), set(df['region'].unique()))


class TestCorrelationAnalysis(unittest.TestCase):
    def test_returns_symmetric_matrix(self):
        df = make_sample_df()
        corr = correlation_analysis(df)
        self.assertIsInstance(corr, pd.DataFrame)
        self.assertEqual(corr.shape[0], corr.shape[1])

    def test_diagonal_is_one(self):
        df = make_sample_df()
        corr = correlation_analysis(df)
        np.testing.assert_array_almost_equal(np.diag(corr.values), 1.0)


class TestAnovaTest(unittest.TestCase):
    def test_returns_dict_with_keys(self):
        df = make_sample_df()
        result = anova_test(df, 'region', 'sales')
        self.assertIn('f_statistic', result)
        self.assertIn('p_value', result)

    def test_p_value_between_0_and_1(self):
        df = make_sample_df()
        result = anova_test(df, 'region', 'sales')
        self.assertGreaterEqual(result['p_value'], 0.0)
        self.assertLessEqual(result['p_value'], 1.0)


class TestLinearRegression(unittest.TestCase):
    def test_returns_dict_with_keys(self):
        df = make_sample_df()
        result = linear_regression(df, 'quantity', 'sales')
        for key in ['slope', 'intercept', 'r_squared', 'p_value']:
            self.assertIn(key, result)

    def test_r_squared_between_0_and_1(self):
        df = make_sample_df()
        result = linear_regression(df, 'quantity', 'sales')
        self.assertGreaterEqual(result['r_squared'], 0.0)
        self.assertLessEqual(result['r_squared'], 1.0)


class TestProfitRateByCategory(unittest.TestCase):
    def test_returns_dataframe(self):
        df = make_sample_df()
        result = profit_rate_by_category(df)
        self.assertIsInstance(result, pd.DataFrame)

    def test_has_expected_columns(self):
        df = make_sample_df()
        result = profit_rate_by_category(df)
        self.assertIn('avg_profit_margin', result.columns)


if __name__ == '__main__':
    unittest.main(verbosity=2)
