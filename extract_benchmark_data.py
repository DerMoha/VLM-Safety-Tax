import os
import json
import pandas as pd

def parse_folder_name(folder_name):
    """Parse folder name to extract benchmark and model information"""
    
    # Handle VQA format: vqa:model=ModelName
    if folder_name.startswith('vqa:model='):
        benchmark = "vqa"
        model = folder_name.split('vqa:model=')[1].strip()
        return benchmark, model
    
    # Handle comma-separated format for other benchmarks
    parts = folder_name.split(',')
    
    benchmark = ""
    model = ""
    
    for part in parts:
        if 'subject=' in part or 'category=' in part or 'subset=' in part:
            benchmark = part.strip()
        elif 'model=' in part:
            model = part.split('model=')[1].strip()
    
    # If no specific benchmark found but we have a model, use the first part as benchmark
    if not benchmark and model:
        benchmark = parts[0].strip()
    
    return benchmark, model

def extract_all_metrics_consolidated(stats_file_path):
    """Extract ALL metrics from stats.json with consolidated split naming"""
    try:
        with open(stats_file_path, 'r') as f:
            data = json.load(f)
        
        metrics = {}
        
        # Extract all metrics without perturbations
        for item in data:
            metric_name = item['name']['name']
            split = item['name']['split']
            
            # Skip perturbation variants
            if 'perturbation' in item['name']:
                continue
                
            # Create consolidated metric name (without split suffix)
            consolidated_key = metric_name
            
            # If we already have this metric, prioritize certain splits
            if consolidated_key in metrics:
                # Priority: test > valid for most metrics
                if split == 'test' and consolidated_key in metrics:
                    # Test split takes priority
                    pass
                elif split == 'valid' and consolidated_key in metrics:
                    # Only update if we don't already have a test split
                    current_split = metrics.get(f"{consolidated_key}_split", "")
                    if current_split != 'test':
                        pass
                    else:
                        continue
                else:
                    continue
            
            # Store the mean value
            if 'mean' in item:
                metrics[consolidated_key] = item['mean']
                # Keep track of which split was used for reference
                metrics[f"{consolidated_key}_split"] = split
            else:
                metrics[consolidated_key] = None
                metrics[f"{consolidated_key}_split"] = split
        
        # Remove the split tracking columns from final output
        final_metrics = {k: v for k, v in metrics.items() if not k.endswith('_split')}
        
        return final_metrics
    except Exception as e:
        print(f"Error reading {stats_file_path}: {e}")
        return {}

def process_folders_consolidated(root_directory):
    """Process all folders and extract ALL metrics with consolidated naming"""
    results = []
    all_metric_names = set()  # To track all possible metrics
    
    # First pass: collect all possible metric names
    for folder_name in os.listdir(root_directory):
        folder_path = os.path.join(root_directory, folder_name)
        
        if not os.path.isdir(folder_path):
            continue
            
        stats_file = os.path.join(folder_path, 'stats.json')
        
        if os.path.exists(stats_file):
            metrics = extract_all_metrics_consolidated(stats_file)
            all_metric_names.update(metrics.keys())
    
    # Second pass: extract data with all metrics
    for folder_name in os.listdir(root_directory):
        folder_path = os.path.join(root_directory, folder_name)
        
        if not os.path.isdir(folder_path):
            continue
            
        stats_file = os.path.join(folder_path, 'stats.json')
        
        if os.path.exists(stats_file):
            benchmark, model = parse_folder_name(folder_name)
            metrics = extract_all_metrics_consolidated(stats_file)
            
            # Create a row with all possible metrics
            row = {
                'Folder_Name': folder_name,
                'Benchmark': benchmark,
                'Model': model
            }
            
            # Add all metrics (fill missing ones with None/NaN)
            for metric_name in sorted(all_metric_names):
                row[metric_name] = metrics.get(metric_name, None)
            
            results.append(row)
            print(f"Processed: {folder_name} -> {len(metrics)} metrics extracted")
        else:
            print(f"No stats.json found in: {folder_name}")
    
    return results, sorted(all_metric_names)

def main():
    # Set the root directory where your folders are located
    root_directory = "/home/stud/hamid/data8/VHELM/benchmark_output/runs/qwen2vl-1k"
    
    print("Processing folders for ALL metrics (consolidated)...")
    results, all_metrics = process_folders_consolidated(root_directory)
    
    if results:
        # Create DataFrame
        df = pd.DataFrame(results)
        
        # Sort by benchmark and model for better organization
        df = df.sort_values(['Benchmark', 'Model'])
        
        # Save complete data to CSV
        output_file = 'complete_benchmark_data_consolidated.csv'
        df.to_csv(output_file, index=False)
        
        print(f"\nComplete results saved to {output_file}")
        print(f"Total records: {len(results)}")
        print(f"Total unique metrics: {len(all_metrics)}")
        
        # Display basic info
        print("\nDataset info:")
        print(f"Columns: {len(df.columns)}")
        print(f"Rows: {len(df)}")
        
        # Show first few columns
        print(f"\nFirst few columns: {list(df.columns[:10])}")
        
        # Show available metrics by type
        print(f"\nSample of available metrics:")
        for i, metric in enumerate(all_metrics[:20]):  # Show first 20 metrics
            print(f"  - {metric}")
        if len(all_metrics) > 20:
            print(f"  ... and {len(all_metrics) - 20} more metrics")
        
        # Create a summary of key metrics (consolidated names)
        key_metrics = ['exact_match', 'quasi_exact_match', 'f1_score', 'quasi_prefix_exact_match']
        
        summary_data = []
        for _, row in df.iterrows():
            summary_row = {
                'Benchmark': row['Benchmark'],
                'Model': row['Model']
            }
            for metric in key_metrics:
                if metric in df.columns:
                    summary_row[metric] = row[metric]
                else:
                    summary_row[metric] = 'N/A'
            summary_data.append(summary_row)
        
        summary_df = pd.DataFrame(summary_data)
        summary_output = 'benchmark_summary_consolidated.csv'
        summary_df.to_csv(summary_output, index=False)
        print(f"\nKey metrics summary saved to {summary_output}")
        
    else:
        print("No data found. Please check your folder structure and file paths.")

if __name__ == "__main__":
    main()
