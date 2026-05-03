import sys
from pathlib import Path
import json
from datetime import datetime

# Add backend directory to path
backend_dir = Path(__file__).resolve().parent
sys.path.insert(0, str(backend_dir))

from app.services.data_augmentation import augment_clean_dataset


def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Augment clean dataset with block bootstrap + jitter"
    )
    parser.add_argument(
        "--input",
        type=str,
        default="clean_dataset.csv",
        help="Input clean dataset CSV",
    )
    parser.add_argument(
        "--output",
        type=str,
        default="clean_dataset_augmented.csv",
        help="Output augmented CSV",
    )
    parser.add_argument(
        "--multiplier",
        type=float,
        default=3.0,
        help="Target size multiplier (e.g., 3.0 = 3x rows)",
    )
    parser.add_argument(
        "--block-size",
        type=int,
        default=12,
        help="Contiguous block size for bootstrap (rows)",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Random seed",
    )

    args = parser.parse_args()

    augmented_df = augment_clean_dataset(
        input_csv=args.input,
        output_csv=args.output,
        multiplier=args.multiplier,
        block_size=args.block_size,
        seed=args.seed,
    )

    metadata = {
        "created_at": datetime.now().isoformat(),
        "input_csv": args.input,
        "output_csv": args.output,
        "multiplier": args.multiplier,
        "block_size": args.block_size,
        "num_records": len(augmented_df),
    }

    metadata_path = args.output.replace(".csv", "_metadata.json")
    with open(metadata_path, "w") as f:
        json.dump(metadata, f, indent=2)

    print(f"Augmented dataset saved to: {args.output}")
    print(f"Metadata saved to: {metadata_path}")


if __name__ == "__main__":
    main()
