import json
import glob
import os
import sys
import pandas as pd
import matplotlib
# Use non-interactive backend when --no-show flag passed or no display available
if '--no-show' in sys.argv or not os.environ.get('DISPLAY', '') and sys.platform != 'darwin':
    matplotlib.use('Agg')
import matplotlib.pyplot as plt
import seaborn as sns
from datetime import datetime

SHOW_PLOTS = '--no-show' not in sys.argv

class BenchmarkAnalyzer:
    def __init__(self, results_dir="results"):
        self.results_dir = results_dir
        self.data = []
        self.setup_plotting()
    
    def setup_plotting(self):
        plt.style.use('seaborn-v0_8')
        sns.set_palette("husl")
        self.fig_size = (12, 8)
    
    def load_results(self, pattern="*.json"):
        """Загружает все JSON результаты"""
        files = glob.glob(os.path.join(self.results_dir, pattern))
        
        for file in files:
            try:
                with open(file, 'r') as f:
                    raw = f.read()
                # Robust: skip any progress-bar prefix before the JSON object
                start = raw.index('{')
                result = json.loads(raw[start:])

                # Извлекаем информацию из имени файла
                filename = os.path.basename(file)
                parts = filename.split('_')
                lb_name = parts[0]
                concurrency = int(parts[1].replace('c', ''))

                r = result['result']
                lat = r['latency']
                # Latency values are in microseconds -> convert to ms
                self.data.append({
                    'load_balancer': lb_name,
                    'concurrency': concurrency,
                    'rps': r['rps']['mean'],
                    'latency_mean': lat['mean'] / 1000,
                    'latency_p50': lat['percentiles']['50'] / 1000,
                    'latency_p90': lat['percentiles']['90'] / 1000,
                    'latency_p95': lat['percentiles']['95'] / 1000,
                    'latency_p99': lat['percentiles']['99'] / 1000,
                    'throughput': r['bytesRead'] / r['timeTakenSeconds'] / 1024 / 1024,
                    'requests_total': r['req2xx'] + r['req1xx'] + r['req3xx'] + r['req4xx'] + r['req5xx'],
                    'errors': r['others'],
                    'file': filename
                })
            except Exception as e:
                print(f"Error loading {file}: {e}")
        
        return pd.DataFrame(self.data)
    
    def create_comparison_plots(self, df):
        """Создает сравнительные графики"""
        fig, axes = plt.subplots(2, 2, figsize=(15, 12))
        
        # RPS по уровню конкурентности
        self._plot_metric_by_concurrency(df, 'rps', 'Requests per Second (RPS)', axes[0, 0])
        
        # Средняя задержка по уровню конкурентности
        self._plot_metric_by_concurrency(df, 'latency_mean', 'Mean Latency (ms)', axes[0, 1])
        
        # P95 задержка
        self._plot_metric_by_concurrency(df, 'latency_p95', 'P95 Latency (ms)', axes[1, 0])
        
        # Пропускная способность
        self._plot_metric_by_concurrency(df, 'throughput', 'Throughput (MB/s)', axes[1, 1])
        
        plt.tight_layout()
        plt.savefig(f'{self.results_dir}/comparison_summary.png', dpi=300, bbox_inches='tight')
        if SHOW_PLOTS:
            plt.show()
    
    def _plot_metric_by_concurrency(self, df, metric, title, ax):
        """Вспомогательная функция для построения графиков"""
        pivot_data = df.pivot_table(
            index='concurrency', 
            columns='load_balancer', 
            values=metric,
            aggfunc='mean'
        )
        
        pivot_data.plot(marker='o', linewidth=2, ax=ax)
        ax.set_title(title, fontsize=14, fontweight='bold')
        ax.set_xlabel('Concurrency Level', fontsize=12)
        ax.set_ylabel(title, fontsize=12)
        ax.grid(True, alpha=0.3)
        ax.legend()
    
    def create_latency_distribution(self, df):
        """График распределения задержек"""
        latency_metrics = ['latency_mean', 'latency_p50', 'latency_p90', 'latency_p95', 'latency_p99']
        concurrency_levels = sorted(df['concurrency'].unique())
        n = len(concurrency_levels)
        cols = min(n, 3)
        rows = (n + cols - 1) // cols
        plt.figure(figsize=(6 * cols, 5 * rows))

        for i, conc in enumerate(concurrency_levels):
            plt.subplot(rows, cols, i + 1)
            conc_data = df[df['concurrency'] == conc]
            
            # Подготовка данных для группированного bar plot
            metrics_data = []
            for lb in conc_data['load_balancer'].unique():
                lb_data = conc_data[conc_data['load_balancer'] == lb].iloc[0]
                for metric in latency_metrics:
                    metrics_data.append({
                        'load_balancer': lb,
                        'metric': metric.replace('latency_', '').upper(),
                        'value': lb_data[metric]
                    })
            
            metrics_df = pd.DataFrame(metrics_data)
            
            sns.barplot(data=metrics_df, x='metric', y='value', hue='load_balancer')
            plt.title(f'Latency Distribution (Concurrency: {conc})', fontweight='bold')
            plt.xlabel('Percentile')
            plt.ylabel('Latency (ms)')
            plt.xticks(rotation=45)
            plt.legend()
        
        plt.tight_layout()
        plt.savefig(f'{self.results_dir}/latency_distribution.png', dpi=300, bbox_inches='tight')
        if SHOW_PLOTS:
            plt.show()
    
    def generate_report(self, df):
        """Генерирует текстовый отчет"""
        report_file = f'{self.results_dir}/benchmark_report_{datetime.now().strftime("%Y%m%d_%H%M%S")}.txt'
        
        with open(report_file, 'w') as f:
            f.write("LOAD BALANCER BENCHMARK REPORT\n")
            f.write("=" * 50 + "\n\n")
            
            # Сводка по RPS
            f.write("REQUESTS PER SECOND (RPS) SUMMARY:\n")
            f.write("-" * 40 + "\n")
            rps_summary = df.groupby(['load_balancer', 'concurrency'])['rps'].mean().unstack()
            f.write(str(rps_summary) + "\n\n")
            
            # Сводка по задержкам
            f.write("MEAN LATENCY SUMMARY (ms):\n")
            f.write("-" * 40 + "\n")
            latency_summary = df.groupby(['load_balancer', 'concurrency'])['latency_mean'].mean().unstack()
            f.write(str(latency_summary) + "\n\n")
            
            # Лучшие результаты
            f.write("BEST PERFORMERS:\n")
            f.write("-" * 40 + "\n")
            
            max_rps = df.loc[df['rps'].idxmax()]
            f.write(f"Highest RPS: {max_rps['load_balancer']} - {max_rps['rps']:.2f} req/sec (concurrency: {max_rps['concurrency']})\n")
            
            min_latency = df.loc[df['latency_mean'].idxmin()]
            f.write(f"Lowest Latency: {min_latency['load_balancer']} - {min_latency['latency_mean']:.2f} ms (concurrency: {min_latency['concurrency']})\n")
        
        print(f"Report generated: {report_file}")

# Основная execution часть
if __name__ == "__main__":
    analyzer = BenchmarkAnalyzer()
    
    print("Loading benchmark results...")
    df = analyzer.load_results()
    
    if df.empty:
        print("No results found! Please run the benchmark first.")
        exit(1)
    
    print(f"Loaded {len(df)} test results")
    print("\nFirst few rows:")
    print(df[['load_balancer', 'concurrency', 'rps', 'latency_mean']].head())
    
    # Создаем визуализации
    print("\nCreating visualizations...")
    analyzer.create_comparison_plots(df)
    analyzer.create_latency_distribution(df)
    
    # Генерируем отчет
    print("\nGenerating report...")
    analyzer.generate_report(df)
    
    print("\nAnalysis complete! Check the 'results' directory for outputs.")