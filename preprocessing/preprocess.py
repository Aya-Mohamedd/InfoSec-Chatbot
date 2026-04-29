"""
CISC 886 - Cloud Computing
PySpark Preprocessing Pipeline for InfoSec Q&A Dataset
Author: Group 1

This script runs on AWS EMR and performs:
1. Loading the raw JSONL dataset from S3
2. Cleaning and normalizing text fields
3. Computing token-level statistics
4. Generating EDA figures (saved to S3)
5. Saving the cleaned, split datasets back to S3 as Parquet
"""

import sys
import json
import os

# ── PySpark imports ──────────────────────────────────────────────────────────
from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.types import StringType, IntegerType

# ── Matplotlib (available on EMR by default) ─────────────────────────────────
import matplotlib
matplotlib.use("Agg")          # non-interactive backend — required on EMR
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker

# ── boto3 for uploading figures to S3 ────────────────────────────────────────
import boto3

# =============================================================================
# CONFIGURATION — change only these two lines
# =============================================================================
S3_BUCKET  = "group1-infosec-bucket"   # <-- replace with your bucket name
NETID      = "group1"                   # <-- replace with your Queen's netID

S3_INPUT   = f"s3://{S3_BUCKET}/input/"
S3_OUTPUT  = f"s3://{S3_BUCKET}/output/"
S3_FIGURES = f"s3://{S3_BUCKET}/figures/"

TMP_FIG_DIR = "/tmp/figures"              # local temp dir on EMR master node

# =============================================================================
# 1. Start Spark Session
# =============================================================================
# We name the app with the netID so it appears correctly in the EMR UI.
spark = SparkSession.builder \
    .appName(f"{NETID}-infosec-preprocessing") \
    .getOrCreate()

spark.sparkContext.setLogLevel("WARN")    # reduce noisy INFO logs
print("✅ Spark session started.")

# =============================================================================
# 2. Load raw JSONL dataset from S3
# =============================================================================
# Spark can read JSONL (one JSON object per line) natively with read.json().
# We load the full dataset as well as each split separately.
print("📂 Loading dataset from S3...")

df_full  = spark.read.json(S3_INPUT + "infosec_dataset.jsonl")
df_train = spark.read.json(S3_INPUT + "infosec_train.jsonl")
df_val   = spark.read.json(S3_INPUT + "infosec_val.jsonl")
df_test  = spark.read.json(S3_INPUT + "infosec_test.jsonl")

print(f"   Full dataset rows  : {df_full.count()}")
print(f"   Train rows         : {df_train.count()}")
print(f"   Validation rows    : {df_val.count()}")
print(f"   Test rows          : {df_test.count()}")

# Print schema so we can confirm the columns look right
df_full.printSchema()
df_full.show(3, truncate=80)

# =============================================================================
# 3. Text Cleaning
# =============================================================================
# We apply the same cleaning steps to every split:
#   a) Strip leading/trailing whitespace from both fields
#   b) Collapse multiple internal spaces into one
#   c) Drop any rows where instruction or response is null/empty

def clean_df(df):
    """Apply text normalization to a dataframe with instruction/response cols."""
    return (
        df
        # (a) strip whitespace from both ends
        .withColumn("instruction", F.trim(F.col("instruction")))
        .withColumn("response",    F.trim(F.col("response")))
        # (b) collapse multiple spaces → single space using regexp_replace
        .withColumn("instruction", F.regexp_replace("instruction", r"\s+", " "))
        .withColumn("response",    F.regexp_replace("response",    r"\s+", " "))
        # (c) drop rows with null or empty strings in either column
        .filter(
            F.col("instruction").isNotNull() & (F.length("instruction") > 0) &
            F.col("response").isNotNull()    & (F.length("response")    > 0)
        )
    )

df_full_clean  = clean_df(df_full)
df_train_clean = clean_df(df_train)
df_val_clean   = clean_df(df_val)
df_test_clean  = clean_df(df_test)

print(f"✅ Cleaning complete. Rows after cleaning — full: {df_full_clean.count()}")

# =============================================================================
# 4. Feature Engineering — Token Count Columns
# =============================================================================
# We approximate token count using whitespace-based word count.
# This is a fast proxy; real tokenizers (BPE) produce slightly higher counts.
# We add these columns so we can plot distributions in the EDA section.

def add_token_counts(df):
    """Add word-count columns as a token length proxy."""
    return (
        df
        .withColumn(
            "instruction_tokens",
            F.size(F.split(F.col("instruction"), r"\s+")).cast(IntegerType())
        )
        .withColumn(
            "response_tokens",
            F.size(F.split(F.col("response"), r"\s+")).cast(IntegerType())
        )
        # total_tokens = instruction + response (useful for context window checks)
        .withColumn(
            "total_tokens",
            F.col("instruction_tokens") + F.col("response_tokens")
        )
    )

df_full_clean  = add_token_counts(df_full_clean)
df_train_clean = add_token_counts(df_train_clean)
df_val_clean   = add_token_counts(df_val_clean)
df_test_clean  = add_token_counts(df_test_clean)

# =============================================================================
# 5. Summary Statistics (printed to EMR logs)
# =============================================================================
print("\n📊 Summary statistics for full cleaned dataset:")
df_full_clean.select(
    "instruction_tokens", "response_tokens", "total_tokens"
).describe().show()

# =============================================================================
# 6. Collect data to driver for plotting
# =============================================================================
# Matplotlib runs on the driver node only, so we collect the columns we need.
# With 111 rows this is perfectly safe; for large datasets you would sample first.
print("📈 Collecting data for EDA figures...")

instr_tokens = [r["instruction_tokens"] for r in
                df_full_clean.select("instruction_tokens").collect()]
resp_tokens  = [r["response_tokens"]    for r in
                df_full_clean.select("response_tokens").collect()]
total_tokens = [r["total_tokens"]       for r in
                df_full_clean.select("total_tokens").collect()]

split_counts = {
    "Train\n(n=88)": df_train_clean.count(),
    "Val\n(n=11)":   df_val_clean.count(),
    "Test\n(n=12)":  df_test_clean.count(),
}

os.makedirs(TMP_FIG_DIR, exist_ok=True)

# ── Figure style ─────────────────────────────────────────────────────────────
COLORS = {
    "instr":  "#2196F3",   # blue
    "resp":   "#4CAF50",   # green
    "total":  "#FF9800",   # orange
    "splits": ["#2196F3", "#4CAF50", "#FF9800"],
}
plt.rcParams.update({
    "figure.facecolor": "white",
    "axes.facecolor":   "white",
    "axes.grid":        True,
    "grid.alpha":       0.3,
    "font.size":        11,
})

# =============================================================================
# EDA Figure 1 — Instruction Token Length Distribution
# =============================================================================
fig1, ax1 = plt.subplots(figsize=(8, 4))
ax1.hist(instr_tokens, bins=12, color=COLORS["instr"], edgecolor="white", linewidth=0.8)
ax1.set_title("Figure 1 — Instruction Token Length Distribution", fontsize=13, fontweight="bold")
ax1.set_xlabel("Word count (whitespace-tokenized)", fontsize=11)
ax1.set_ylabel("Number of samples", fontsize=11)
ax1.axvline(sum(instr_tokens)/len(instr_tokens), color="navy",
            linestyle="--", linewidth=1.5,
            label=f"Mean = {sum(instr_tokens)/len(instr_tokens):.1f}")
ax1.legend()
fig1.tight_layout()
fig1_path = os.path.join(TMP_FIG_DIR, "fig1_instruction_token_dist.png")
fig1.savefig(fig1_path, dpi=150)
plt.close(fig1)
print(f"   Saved: {fig1_path}")

# =============================================================================
# EDA Figure 2 — Response Token Length Distribution
# =============================================================================
fig2, ax2 = plt.subplots(figsize=(8, 4))
ax2.hist(resp_tokens, bins=15, color=COLORS["resp"], edgecolor="white", linewidth=0.8)
ax2.set_title("Figure 2 — Response Token Length Distribution", fontsize=13, fontweight="bold")
ax2.set_xlabel("Word count (whitespace-tokenized)", fontsize=11)
ax2.set_ylabel("Number of samples", fontsize=11)
ax2.axvline(sum(resp_tokens)/len(resp_tokens), color="darkgreen",
            linestyle="--", linewidth=1.5,
            label=f"Mean = {sum(resp_tokens)/len(resp_tokens):.1f}")
ax2.legend()
fig2.tight_layout()
fig2_path = os.path.join(TMP_FIG_DIR, "fig2_response_token_dist.png")
fig2.savefig(fig2_path, dpi=150)
plt.close(fig2)
print(f"   Saved: {fig2_path}")

# =============================================================================
# EDA Figure 3 — Sample Count per Split (Bar Chart)
# =============================================================================
fig3, ax3 = plt.subplots(figsize=(7, 4))
bars = ax3.bar(split_counts.keys(), split_counts.values(),
               color=COLORS["splits"], edgecolor="white", linewidth=0.8, width=0.5)
ax3.set_title("Figure 3 — Sample Count per Split", fontsize=13, fontweight="bold")
ax3.set_xlabel("Dataset Split", fontsize=11)
ax3.set_ylabel("Number of samples", fontsize=11)
ax3.yaxis.set_major_locator(ticker.MaxNLocator(integer=True))
for bar, val in zip(bars, split_counts.values()):
    ax3.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.5,
             str(val), ha="center", va="bottom", fontweight="bold", fontsize=12)
fig3.tight_layout()
fig3_path = os.path.join(TMP_FIG_DIR, "fig3_split_counts.png")
fig3.savefig(fig3_path, dpi=150)
plt.close(fig3)
print(f"   Saved: {fig3_path}")

# =============================================================================
# 7. Upload figures to S3
# =============================================================================
# We use boto3 (pre-installed on EMR) to upload the local PNG files to S3.
print("☁️  Uploading figures to S3...")
s3_client = boto3.client("s3")

for fig_path in [fig1_path, fig2_path, fig3_path]:
    filename = os.path.basename(fig_path)
    s3_key   = f"figures/{filename}"
    s3_client.upload_file(fig_path, S3_BUCKET, s3_key)
    print(f"   Uploaded: s3://{S3_BUCKET}/{s3_key}")

print("✅ All figures uploaded.")

# =============================================================================
# 8. Save cleaned datasets to S3 as Parquet
# =============================================================================
# Parquet is a columnar format ideal for downstream Spark/ML workloads.
# We save each split separately so the fine-tuning notebook can load them easily.
print("💾 Saving cleaned datasets to S3 as Parquet...")

df_train_clean.write.mode("overwrite").parquet(S3_OUTPUT + "train/")
df_val_clean.write.mode("overwrite").parquet(S3_OUTPUT + "val/")
df_test_clean.write.mode("overwrite").parquet(S3_OUTPUT + "test/")

# Also save the full cleaned dataset
df_full_clean.write.mode("overwrite").parquet(S3_OUTPUT + "full/")

print(f"✅ Cleaned datasets saved to: {S3_OUTPUT}")

# =============================================================================
# 9. Save a cleaned JSONL version as well (for fine-tuning notebook)
# =============================================================================
# The fine-tuning notebook expects JSONL, not Parquet, so we also export that.
# We use coalesce(1) to write a single file instead of many partitioned files.
df_train_clean.select("instruction", "response") \
    .coalesce(1).write.mode("overwrite") \
    .json(S3_OUTPUT + "train_jsonl/")

df_val_clean.select("instruction", "response") \
    .coalesce(1).write.mode("overwrite") \
    .json(S3_OUTPUT + "val_jsonl/")

df_test_clean.select("instruction", "response") \
    .coalesce(1).write.mode("overwrite") \
    .json(S3_OUTPUT + "test_jsonl/")

print("✅ JSONL outputs saved.")

# =============================================================================
# 10. Final verification — print counts one more time
# =============================================================================
print("\n" + "="*60)
print("PREPROCESSING COMPLETE — Final row counts:")
print(f"  Full  : {df_full_clean.count()}")
print(f"  Train : {df_train_clean.count()}")
print(f"  Val   : {df_val_clean.count()}")
print(f"  Test  : {df_test_clean.count()}")
print("="*60)

spark.stop()
print("✅ Spark session stopped. Job complete.")
