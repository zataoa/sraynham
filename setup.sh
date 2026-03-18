#!/usr/bin/env bash
set -euo pipefail

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║   BitNet Autoresearch Setup                      ║"
echo "║   Fine-tune BitNet-b1.58-2B-4T overnight         ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ── Guard: warn if already set up ────────────────────────────────────────────
if [[ -f "CLAUDE.md" ]]; then
    echo "WARNING: Generated files already exist (CLAUDE.md found)."
    read -rp "Overwrite existing setup? [y/N]: " CONFIRM
    CONFIRM="${CONFIRM:-N}"
    if [[ "${CONFIRM,,}" != "y" ]]; then
        echo "Aborted. Existing setup preserved."
        exit 0
    fi
    echo ""
fi

# ── Collect inputs ────────────────────────────────────────────────────────────
echo "==> What should BitNet become an expert in?"
echo ""
read -rp "Domain/skill (e.g. 'Rust coding', 'medical Q&A', 'creative writing'): " DOMAIN
echo ""
echo "Describe the ideal behaviour in one or two sentences."
read -rp "Behaviour description: " BEHAVIOUR
echo ""
echo "==> Training data"
echo ""
echo "Enter a HuggingFace dataset ID, or leave blank to generate synthetic seed data."
echo "Examples: iamtarun/python_code_instructions_18k_alpaca  yahma/alpaca-cleaned  gsm8k"
read -rp "HuggingFace dataset [leave blank for synthetic]: " DATASET
echo ""
echo "==> Experiment budget"
echo ""
read -rp "Minutes per experiment [5]: " BUDGET
BUDGET="${BUDGET:-5}"
read -rp "Session tag [$(date +%b%d | tr '[:upper:]' '[:lower:]')]: " SESSION_TAG
SESSION_TAG="${SESSION_TAG:-$(date +%b%d | tr '[:upper:]' '[:lower:]')}"
echo ""

DATASET_DISPLAY="${DATASET:-synthetic seed data}"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# ── Generate CLAUDE.md ────────────────────────────────────────────────────────
cat > CLAUDE.md << 'HEREDOC'
# BitNet Autoresearch — Claude Code Instructions

You are an autonomous ML research agent running Karpathy's Autoresearch methodology
to fine-tune `microsoft/bitnet-b1.58-2B-4T-bf16` into a domain expert.

**Domain:** DOMAIN_PLACEHOLDER
**Behaviour target:** BEHAVIOUR_PLACEHOLDER
**Time budget per experiment:** BUDGET_PLACEHOLDER minutes

---

## Files you MAY edit

- `finetune.py` — the training script. This is your only mutation target.

## Files you MUST NOT edit

- `prepare.py` — data pipeline (fixed)
- `program.md` — your research directive (fixed)
- `CLAUDE.md` — this file (fixed)

## Files you append to (never overwrite)

- `lab_notebook.md` — one entry per experiment, appended below `## Experiments`
- `results.tsv` — one TSV row per experiment, appended after the header

## Files you overwrite after each experiment

- `last_result.json` — the most recent result (overwrite each time)

---

## The ratchet rule

After every experiment:
- If `val_loss` improved (lower than `BEST_VAL_LOSS`):
  - `git add finetune.py results.tsv lab_notebook.md last_result.json`
  - `git commit -m "improvement: val_loss=VALUE — one-line description"`
  - Update `BEST_VAL_LOSS`
- If `val_loss` did not improve:
  - `git checkout finetune.py` to revert
  - Log the outcome in `lab_notebook.md` and `results.tsv`
  - Do NOT commit

Only improvements survive. The git log is a record of every win.

---

## Result protocol

`finetune.py` always prints `VAL_LOSS=<float>` as its **final stdout line**.

Parse it with:
```bash
VAL_LOSS=$(python finetune.py 2>&1 | tail -1 | sed 's/VAL_LOSS=//')
```
Or read `last_result.json` which `finetune.py` writes before printing that line.

---

## Constraints on finetune.py

These must NEVER be removed or changed:
1. `replace_linear_with_bitnet_linear(model)` — the 1.58-bit conversion call
2. `MODEL_ID = "microsoft/bitnet-b1.58-2B-4T-bf16"` — the base model (bf16 variant, required for training)
3. The `print(f"VAL_LOSS={val_loss:.6f}")` final line
4. Data loading from `data/train.jsonl` and `data/val.jsonl`

---

## Detailed instructions

Read `program.md` for the full Phase 1 / Phase 2 protocol.
HEREDOC

sed -i "s|DOMAIN_PLACEHOLDER|${DOMAIN}|g" CLAUDE.md
sed -i "s|BEHAVIOUR_PLACEHOLDER|${BEHAVIOUR}|g" CLAUDE.md
sed -i "s|BUDGET_PLACEHOLDER|${BUDGET}|g" CLAUDE.md

# ── Generate program.md ───────────────────────────────────────────────────────
cat > program.md << 'HEREDOC'
# Research Directive — DOMAIN_PLACEHOLDER

**Domain:** DOMAIN_PLACEHOLDER
**Behaviour target:** BEHAVIOUR_PLACEHOLDER
**Base model:** microsoft/bitnet-b1.58-2B-4T-bf16
**Metric:** val_loss (lower is better)
**Time budget per experiment:** BUDGET_PLACEHOLDER minutes
**Dataset:** DATASET_PLACEHOLDER

---

## Protocol

You will run two phases. Phase 1 runs once. Phase 2 loops forever.

---

## Phase 1 — Setup (run once)

1. Create and checkout a research branch:
   ```
   git checkout -b autoresearch/SESSION_TAG_PLACEHOLDER
   ```

2. Run the data pipeline:
   ```
   python prepare.py
   ```
   This creates `data/train.jsonl` and `data/val.jsonl`. Do not edit these files.

3. Run the baseline experiment:
   ```
   python finetune.py 2>&1 | tee /tmp/baseline.log
   ```
   Capture the final line: `VAL_LOSS=<float>`. This is your BASELINE_VAL_LOSS.

4. Write the baseline entry in `lab_notebook.md`:
   ```markdown
   ## Baseline

   **val_loss:** <VALUE>
   **Notes:** Unmodified finetune.py defaults.
   ```

5. Append the baseline row to `results.tsv`:
   ```
   <timestamp>\t<val_loss>\t<lora_r>\t<learning_rate>\t<batch_size>\t<grad_accum>\t<max_seq_len>\t<steps>\ttrue\tbaseline
   ```
   (Get hyperparameter values from `last_result.json` which finetune.py writes.)

6. Commit the baseline:
   ```
   git add results.tsv lab_notebook.md last_result.json
   git commit -m "baseline: val_loss=<VALUE>"
   ```

7. Set BEST_VAL_LOSS = BASELINE_VAL_LOSS. Begin Phase 2.

---

## Phase 2 — Iterative improvement (loop forever)

Repeat the following loop indefinitely:

**Step 1 — Hypothesise**
Write your hypothesis to `lab_notebook.md` BEFORE making any edits:
```markdown
### Experiment N — <timestamp>

**Hypothesis:** <what you plan to change and why you think it will help>
```

**Step 2 — Edit**
Make exactly one focused change to `finetune.py`. Modify only the HYPERPARAMETERS
block unless you have a strong reason to change something deeper (e.g. the
tokenization format). One change per experiment keeps causality clear.

**Step 3 — Train**
```
python finetune.py 2>&1 | tee /tmp/exp_N.log
```
Capture the final line: `VAL_LOSS=<float>`. Also read `last_result.json`.

**Step 4a — If improved** (val_loss < BEST_VAL_LOSS):
- Update BEST_VAL_LOSS
- Append to `results.tsv`: `<timestamp>\t<val_loss>\t...\ttrue\t<one-line note>`
- Append to `lab_notebook.md`:
  ```markdown
  **Change:** <exact edit>
  **val_loss:** <value> (previous best: <old value>) ✓ improved
  **Notes:** <observations>

  ---
  ```
- Commit:
  ```
  git add finetune.py results.tsv lab_notebook.md last_result.json
  git commit -m "improvement: val_loss=<VALUE> — <one-line summary>"
  ```

**Step 4b — If not improved** (val_loss >= BEST_VAL_LOSS):
- Revert finetune.py:
  ```
  git checkout finetune.py
  ```
- Append to `results.tsv`: `<timestamp>\t<val_loss>\t...\tfalse\t<one-line note>`
- Append to `lab_notebook.md`:
  ```markdown
  **Change:** <exact edit>
  **val_loss:** <value> (best remains: <BEST_VAL_LOSS>) ✗ reverted
  **Notes:** <why this might not have worked>

  ---
  ```
- Do NOT commit.

**Step 5 — Loop**
Go to Step 1.

---

## What to try (roughly in order)

Work through these ideas systematically. After exhausting obvious options, get creative.

1. **Learning rate** — try lower values: 1e-4 → 5e-5 → 2e-5 → 1e-5
2. **Batch size and gradient accumulation** — effective batch = BATCH_SIZE * GRAD_ACCUM
3. **LoRA rank** — try r=4, r=16, r=32, r=64
4. **LoRA alpha** — conventionally 2x rank (alpha=16 for r=8)
5. **LoRA target modules** — add more projections: `k_proj`, `o_proj`, `gate_proj`, `up_proj`, `down_proj`
6. **Warmup** — try warmup_steps 20 → 100 → 200
7. **LR scheduler** — try `linear`, `constant_with_warmup`, `cosine`
8. **Max sequence length** — shorter (256) can fit more steps in the time budget
9. **Weight decay** — try 0.0, 0.01, 0.1
10. **LoRA dropout** — try 0.0, 0.05, 0.1
11. **Gradient clipping** — add `max_grad_norm` to TrainingArguments

---

## Hard constraints (never violate these)

- `replace_linear_with_bitnet_linear(model)` must remain in `load_model()`
- `MODEL_ID = "microsoft/bitnet-b1.58-2B-4T-bf16"` must not change
- `print(f"VAL_LOSS={val_loss:.6f}")` must remain the final line of `finetune.py`
- Data is always loaded from `data/train.jsonl` and `data/val.jsonl`
- Do not edit `prepare.py` or `program.md`
HEREDOC

sed -i "s|DOMAIN_PLACEHOLDER|${DOMAIN}|g" program.md
sed -i "s|BEHAVIOUR_PLACEHOLDER|${BEHAVIOUR}|g" program.md
sed -i "s|BUDGET_PLACEHOLDER|${BUDGET}|g" program.md
sed -i "s|DATASET_PLACEHOLDER|${DATASET_DISPLAY}|g" program.md
sed -i "s|SESSION_TAG_PLACEHOLDER|${SESSION_TAG}|g" program.md

# ── Generate prepare.py ───────────────────────────────────────────────────────
cat > prepare.py << 'HEREDOC'
"""
prepare.py — Data pipeline for BitNet Autoresearch.

This file is FIXED. The agent (Claude Code) must not edit it.

Writes:
  data/train.jsonl  — training examples
  data/val.jsonl    — validation examples

Each line is a JSON object:
  {"instruction": "...", "response": "...", "domain": "DOMAIN_PLACEHOLDER"}
"""

import argparse
import json
import os
import random
import sys

DOMAIN = "DOMAIN_PLACEHOLDER"
BEHAVIOUR = "BEHAVIOUR_PLACEHOLDER"
DATASET_ID = "DATASET_PLACEHOLDER"  # empty string = use synthetic data


# ── Helpers ───────────────────────────────────────────────────────────────────

def write_jsonl(path: str, records: list[dict]) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        for rec in records:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    print(f"  Wrote {len(records):,} records to {path}")


def normalize_record(example: dict) -> dict | None:
    """Map a dataset row to {instruction, response} regardless of column names."""
    # Ordered list of (instruction_key, response_key) pairs to try
    candidates = [
        ("instruction", "output"),
        ("instruction", "response"),
        ("input", "output"),
        ("prompt", "completion"),
        ("prompt", "response"),
        ("question", "answer"),
        ("question", "response"),
        ("text", "label"),
    ]
    for inst_key, resp_key in candidates:
        if inst_key in example and resp_key in example:
            inst = str(example[inst_key] or "").strip()
            resp = str(example[resp_key] or "").strip()
            if inst and resp:
                # Some datasets include a separate "input" context field
                context = str(example.get("input", "") or "").strip()
                if context and inst_key != "input":
                    inst = f"{inst}\n\n{context}"
                return {"instruction": inst, "response": resp}
    # Fallback: use first two non-empty string values
    text_vals = [str(v).strip() for v in example.values() if isinstance(v, str) and str(v).strip()]
    if len(text_vals) >= 2:
        return {"instruction": text_vals[0], "response": text_vals[1]}
    return None


# ── HuggingFace dataset mode ──────────────────────────────────────────────────

def load_from_huggingface(dataset_id: str, train_limit: int = 10000, val_limit: int = 1000) -> tuple[list, list]:
    try:
        from datasets import load_dataset  # type: ignore
    except ImportError:
        print("ERROR: 'datasets' package not installed. Run: pip install datasets")
        sys.exit(1)

    print(f"  Loading dataset: {dataset_id}")
    try:
        ds = load_dataset(dataset_id, trust_remote_code=True)
    except Exception as exc:
        print(f"ERROR loading dataset '{dataset_id}': {exc}")
        sys.exit(1)

    # Prefer 'train' split; fall back to first available split
    if "train" in ds:
        raw = ds["train"]
    else:
        split_name = list(ds.keys())[0]
        print(f"  No 'train' split found; using '{split_name}'")
        raw = ds[split_name]

    print(f"  Raw dataset size: {len(raw):,} rows")
    records = []
    for example in raw:
        rec = normalize_record(dict(example))
        if rec:
            rec["domain"] = DOMAIN
            records.append(rec)
        if len(records) >= train_limit + val_limit:
            break

    if len(records) < 100:
        print(f"WARNING: Only {len(records)} usable records found after normalization.")
        print("Consider a different dataset or use synthetic mode (leave dataset blank in setup.sh).")

    random.shuffle(records)
    return records[:train_limit], records[train_limit:train_limit + val_limit]


# ── Synthetic data mode ───────────────────────────────────────────────────────

INSTRUCTION_TEMPLATES = [
    "Explain the concept of {topic} as it relates to {domain}.",
    "What are the best practices for {topic} in {domain}?",
    "Write a detailed example demonstrating {topic} for {domain}.",
    "What common mistakes should be avoided when working with {topic} in {domain}?",
    "How would you approach {topic} when building a {domain} system?",
    "Compare different approaches to {topic} in the context of {domain}.",
    "What are the trade-offs between different {topic} strategies in {domain}?",
    "Walk me through the process of implementing {topic} for {domain}.",
    "Explain when to use {topic} versus alternatives in {domain}.",
    "What are the key principles behind {topic} that every {domain} practitioner should know?",
]

GENERIC_TOPICS = [
    "error handling",
    "performance optimisation",
    "testing",
    "documentation",
    "code organisation",
    "debugging",
    "refactoring",
    "dependency management",
    "security considerations",
    "scalability",
    "maintainability",
    "readability",
    "design patterns",
    "data modelling",
    "API design",
]


def make_synthetic_response(instruction: str, domain: str, behaviour: str) -> str:
    """Generate a simple synthetic response using templates."""
    return (
        f"Here is a detailed response for the {domain} domain:\n\n"
        f"{instruction}\n\n"
        f"As a {domain} expert, the ideal approach follows these principles:\n"
        f"{behaviour}\n\n"
        f"In practice, you would:\n"
        f"1. Analyse the requirements carefully\n"
        f"2. Apply domain-specific best practices\n"
        f"3. Validate your approach against established patterns\n"
        f"4. Document your reasoning clearly\n\n"
        f"This represents a foundational example. Real implementations should be "
        f"adapted to the specific context and constraints of your project."
    )


def load_synthetic(n_train: int = 400, n_val: int = 100) -> tuple[list, list]:
    print(f"  Generating synthetic seed data for domain: {DOMAIN}")
    random.seed(42)
    records = []
    topics = GENERIC_TOPICS.copy()
    # Pad topics if we need more examples than available
    while len(topics) < n_train + n_val:
        topics.extend(GENERIC_TOPICS)

    random.shuffle(topics)
    for i, topic in enumerate(topics[: n_train + n_val]):
        template = INSTRUCTION_TEMPLATES[i % len(INSTRUCTION_TEMPLATES)]
        instruction = template.format(topic=topic, domain=DOMAIN)
        response = make_synthetic_response(instruction, DOMAIN, BEHAVIOUR)
        records.append({"instruction": instruction, "response": response, "domain": DOMAIN})

    return records[:n_train], records[n_train:]


# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="Prepare training data for BitNet fine-tuning")
    parser.add_argument("--force", action="store_true", help="Overwrite existing data files")
    args = parser.parse_args()

    if os.path.exists("data/train.jsonl") and not args.force:
        print("data/train.jsonl already exists. Pass --force to regenerate.")
        sys.exit(0)

    print(f"\nPreparing data for: {DOMAIN}")
    print(f"Mode: {'HuggingFace dataset: ' + DATASET_ID if DATASET_ID else 'synthetic seed data'}")
    print()

    if DATASET_ID:
        train_records, val_records = load_from_huggingface(DATASET_ID)
    else:
        train_records, val_records = load_synthetic()

    if not val_records:
        # Carve out 10% for validation if the dataset gave us nothing for val
        split = max(1, len(train_records) // 10)
        val_records = train_records[-split:]
        train_records = train_records[:-split]

    print()
    write_jsonl("data/train.jsonl", train_records)
    write_jsonl("data/val.jsonl", val_records)
    print(f"\nDone. Train: {len(train_records):,}  Val: {len(val_records):,}")
    print("Run: python finetune.py")


if __name__ == "__main__":
    main()
HEREDOC

sed -i "s|DOMAIN_PLACEHOLDER|${DOMAIN}|g" prepare.py
sed -i "s|BEHAVIOUR_PLACEHOLDER|${BEHAVIOUR}|g" prepare.py
sed -i "s|DATASET_PLACEHOLDER|${DATASET}|g" prepare.py

# ── Generate finetune.py ──────────────────────────────────────────────────────
cat > finetune.py << 'HEREDOC'
"""
finetune.py — BitNet fine-tuning script for BitNet Autoresearch.

The autonomous agent (Claude Code) edits the HYPERPARAMETERS block below.
Everything else should remain structurally intact.

Final stdout line is always: VAL_LOSS=<float>
"""

import json
import os
import sys
import time
from datetime import datetime, timezone

import torch
from peft import LoraConfig, TaskType, get_peft_model  # type: ignore
from transformers import (  # type: ignore
    AutoModelForCausalLM,
    AutoTokenizer,
    TrainerCallback,
    TrainerControl,
    TrainerState,
    TrainingArguments,
)
from trl import SFTConfig, SFTTrainer  # type: ignore
from datasets import load_dataset  # type: ignore
from onebitllms import replace_linear_with_bitnet_linear  # type: ignore

# ── HYPERPARAMETERS ───────────────────────────────────────────────────────────
# Agent: edit values in this section. Do not change the structure below it.

# Use the bf16 variant — ternary-weight model with bfloat16 masters for training.
# The int8 variant (bitnet-b1.58-2B-4T) cannot be gradient-updated directly.
MODEL_ID        = "microsoft/bitnet-b1.58-2B-4T-bf16"
DOMAIN          = "DOMAIN_PLACEHOLDER"
BUDGET_MINUTES  = BUDGET_PLACEHOLDER         # hard time limit per experiment

# LoRA
LORA_R               = 8
LORA_ALPHA           = 16
LORA_DROPOUT         = 0.05
LORA_TARGET_MODULES  = ["q_proj", "v_proj"]

# Training
LEARNING_RATE   = 2e-4
BATCH_SIZE      = 1
GRAD_ACCUM      = 8                  # effective batch = BATCH_SIZE * GRAD_ACCUM
WARMUP_RATIO    = 0.05
MAX_SEQ_LEN     = 512
WEIGHT_DECAY    = 0.01
LR_SCHEDULER    = "cosine"           # cosine | linear | constant_with_warmup
NUM_EPOCHS      = 999                # effectively infinite — time budget stops it

# ── END HYPERPARAMETERS ───────────────────────────────────────────────────────


class TimeBudgetCallback(TrainerCallback):
    """Stop training gracefully when the time budget is exhausted."""

    def __init__(self, budget_minutes: float) -> None:
        self.deadline = time.time() + budget_minutes * 60.0

    def on_step_end(
        self,
        args: TrainingArguments,
        state: TrainerState,
        control: TrainerControl,
        **kwargs,
    ) -> TrainerControl:
        # Note: fires at step boundaries; actual overshoot ≤ one step duration.
        if time.time() >= self.deadline:
            print(f"\nTime budget ({BUDGET_MINUTES} min) reached at step {state.global_step}. Stopping.")
            control.should_training_stop = True
        return control


def format_example(example: dict) -> dict:
    """Convert {instruction, response} record to a single text field for SFTTrainer."""
    return {
        "text": (
            f"### Instruction:\n{example['instruction']}\n\n"
            f"### Response:\n{example['response']}"
        )
    }


def load_data():
    train_ds = load_dataset("json", data_files="data/train.jsonl", split="train")
    val_ds   = load_dataset("json", data_files="data/val.jsonl",   split="train")
    train_ds = train_ds.map(format_example)
    val_ds   = val_ds.map(format_example)
    return train_ds, val_ds


def compute_val_loss(model, tokenizer, val_ds) -> float:
    """Evaluate mean cross-entropy loss on the validation set (up to 200 examples)."""
    model.eval()
    device = next(model.parameters()).device
    total_loss = 0.0
    n = 0
    with torch.no_grad():
        for example in val_ds.select(range(min(200, len(val_ds)))):
            inputs = tokenizer(
                example["text"],
                return_tensors="pt",
                truncation=True,
                max_length=MAX_SEQ_LEN,
                padding=False,
            ).to(device)
            outputs = model(**inputs, labels=inputs["input_ids"])
            total_loss += outputs.loss.item()
            n += 1
    return total_loss / max(n, 1)


def load_model():
    tokenizer = AutoTokenizer.from_pretrained(MODEL_ID, trust_remote_code=True)
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token

    device_map = {"": 0} if torch.cuda.is_available() else "auto"

    model = AutoModelForCausalLM.from_pretrained(
        MODEL_ID,
        torch_dtype=torch.bfloat16,
        device_map=device_map,
        trust_remote_code=True,
    )

    # REQUIRED: convert linear layers to BitNet 1.58-bit ternary weights.
    # Keeps bfloat16 master weights for gradient updates; quantises during forward.
    # This call must remain. Do not remove or comment out.
    model = replace_linear_with_bitnet_linear(model)

    lora_config = LoraConfig(
        task_type=TaskType.CAUSAL_LM,
        r=LORA_R,
        lora_alpha=LORA_ALPHA,
        lora_dropout=LORA_DROPOUT,
        target_modules=LORA_TARGET_MODULES,
        bias="none",
    )
    model = get_peft_model(model, lora_config)
    model.print_trainable_parameters()
    return model, tokenizer


def main() -> None:
    if not os.path.exists("data/train.jsonl"):
        print("ERROR: data/train.jsonl not found. Run: python prepare.py")
        sys.exit(1)

    print(f"\n{'='*60}")
    print(f"BitNet Autoresearch — {DOMAIN}")
    print(f"Budget: {BUDGET_MINUTES} min | LR: {LEARNING_RATE} | LoRA r={LORA_R}")
    print(f"{'='*60}\n")

    model, tokenizer = load_model()
    train_ds, val_ds = load_data()

    sft_config = SFTConfig(
        output_dir="./checkpoints",
        per_device_train_batch_size=BATCH_SIZE,
        gradient_accumulation_steps=GRAD_ACCUM,
        learning_rate=LEARNING_RATE,
        warmup_ratio=WARMUP_RATIO,
        num_train_epochs=NUM_EPOCHS,
        lr_scheduler_type=LR_SCHEDULER,
        weight_decay=WEIGHT_DECAY,
        bf16=torch.cuda.is_available(),
        fp16=False,
        max_seq_length=MAX_SEQ_LEN,
        dataset_text_field="text",
        logging_steps=10,
        eval_strategy="no",
        save_strategy="no",       # agent manages commits, not Trainer
        report_to="none",         # no wandb/tensorboard
        dataloader_num_workers=0,
    )

    trainer = SFTTrainer(
        model=model,
        args=sft_config,
        train_dataset=train_ds,
        callbacks=[TimeBudgetCallback(BUDGET_MINUTES)],
    )

    trainer.train()

    val_loss = compute_val_loss(model, tokenizer, val_ds)

    # Write last_result.json (read by the agent after each experiment)
    result = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "val_loss": val_loss,
        "hyperparameters": {
            "lora_r": LORA_R,
            "lora_alpha": LORA_ALPHA,
            "lora_dropout": LORA_DROPOUT,
            "lora_target_modules": LORA_TARGET_MODULES,
            "learning_rate": LEARNING_RATE,
            "batch_size": BATCH_SIZE,
            "grad_accum": GRAD_ACCUM,
            "warmup_ratio": WARMUP_RATIO,
            "max_seq_len": MAX_SEQ_LEN,
            "weight_decay": WEIGHT_DECAY,
            "lr_scheduler": LR_SCHEDULER,
        },
        "steps_completed": trainer.state.global_step,
    }
    with open("last_result.json", "w") as fh:
        json.dump(result, fh, indent=2)

    # REQUIRED: this must be the final printed line.
    # The agent parses val_loss from this line. Do not remove or move it.
    print(f"VAL_LOSS={val_loss:.6f}")


if __name__ == "__main__":
    main()
HEREDOC

sed -i "s|DOMAIN_PLACEHOLDER|${DOMAIN}|g" finetune.py
sed -i "s|BUDGET_PLACEHOLDER|${BUDGET}|g" finetune.py

# ── Generate results.tsv ──────────────────────────────────────────────────────
printf 'timestamp\tval_loss\tlora_r\tlearning_rate\tbatch_size\tgrad_accum\tmax_seq_len\tsteps\timproved\tnotes\n' > results.tsv

# ── Generate lab_notebook.md ──────────────────────────────────────────────────
cat > lab_notebook.md << EOF
# Lab Notebook — ${DOMAIN}

**Domain:** ${DOMAIN}
**Behaviour target:** ${BEHAVIOUR}
**Dataset:** ${DATASET_DISPLAY}
**Started:** ${TIMESTAMP}

---

## Baseline

*(To be filled in during Phase 1)*

---

## Experiments

*(Agent appends entries here. Format per entry:)*

<!--
### Experiment N — YYYY-MM-DDTHH:MM:SSZ

**Hypothesis:** what change was made and why
**Change:** exact edit to finetune.py
**val_loss:** VALUE (previous best: VALUE)
**Improved:** yes/no
**Notes:** observations

---
-->
EOF

# ── Git commit ────────────────────────────────────────────────────────────────
git add CLAUDE.md program.md prepare.py finetune.py results.tsv lab_notebook.md .gitignore requirements.txt
git commit -m "chore: autoresearch scaffold for ${DOMAIN}"

# ── Print quickstart ──────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║   Setup complete!                                ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "Domain:   ${DOMAIN}"
echo "Dataset:  ${DATASET_DISPLAY}"
echo "Budget:   ${BUDGET} min/experiment"
echo "Branch:   autoresearch/${SESSION_TAG}  (created by agent in Phase 1)"
echo ""
echo "Next steps:"
echo ""
echo "  1. Install Python dependencies:"
echo "     python3 -m venv .venv && source .venv/bin/activate"
echo "     pip install -r requirements.txt"
echo ""
echo "  2. Prepare training data:"
echo "     python prepare.py"
echo ""
echo "  3. Launch Claude Code and walk away:"
echo "     claude --dangerously-skip-permissions \\"
echo "       \"Read program.md and begin autonomous experimentation. \\"
echo "        Start with Phase 1 setup, then loop Phase 2 indefinitely.\""
echo ""
echo "Monitor progress:"
echo "  tail -f results.tsv          # live experiment metrics"
echo "  cat lab_notebook.md          # agent's reasoning"
echo "  git log --oneline            # committed improvements"
echo ""
