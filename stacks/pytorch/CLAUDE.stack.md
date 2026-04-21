---
source: stacks/pytorch
---

# Stack: PyTorch

Conventions for projects doing model training, fine-tuning, or
inference with PyTorch. Layers on `core/` and `stacks/python`.

## What this covers

- Core PyTorch patterns (tensor discipline, device management, training loops).
- When to use `torch.compile`, AMP, gradient accumulation.
- Dataloader pitfalls (num_workers, pin_memory, distributed sampling).
- Lightning / HF Accelerate / FSDP — when to reach for each.

## What this doesn't cover

- Serving a trained model (see `core/skills/llm-serving` domain hub + `stacks/vllm-ollama`).
- Model architecture design (that's research; this is engineering).
- Prompt / dataset curation — out of scope.

## Version assumption

Target **PyTorch 2.4+**. Patterns below assume modern PyTorch:
`torch.compile`, Autocast, `torch.set_float32_matmul_precision`, FSDP2,
and HF `accelerate`. Legacy patterns (`Variable`, `DataParallel`,
manual FP16) are not recommended.

## Default discipline

- **Reproducibility.** Seed *everything* (`torch.manual_seed`, `numpy.random.seed`, `random.seed`, CUDA seeds) and set deterministic flags where you care. Log hyperparameters and commit SHA with every run.
- **Device-agnostic code.** Never hard-code `.cuda()`. Always `.to(device)` with a device resolved at the top of the script.
- **Explicit dtypes.** `torch.float32` by default; `torch.bfloat16` / `torch.float16` deliberate opt-ins.
- **Separate data / model / training code.** Dataset classes in one module, model in another, training loop in a third. Configs (argparse / hydra / yaml) at the entry point.
- **Log with tensorboard / wandb / mlflow, not `print`.** Metrics, gradient norms, learning rate, GPU memory — the things you'll want to look at when a run goes wrong.

## Project skeleton

```
project/
├── pyproject.toml
├── configs/
│   ├── default.yaml
│   └── experiments/
├── src/
│   ├── data/
│   │   ├── dataset.py
│   │   └── collate.py
│   ├── models/
│   │   └── net.py
│   ├── training/
│   │   ├── loop.py
│   │   └── scheduler.py
│   └── utils/
│       └── seed.py
├── scripts/
│   ├── train.py
│   ├── eval.py
│   └── export.py
└── tests/
```

## Tensor discipline

- **`torch.tensor(data)`** copies; **`torch.as_tensor(data)`** shares memory when dtype/device match. Use the right one.
- **Avoid `.item()` in hot paths.** Synchronizes GPU↔CPU; kills throughput.
- **Avoid `.cpu().numpy()` in training loops** for logging — accumulate on GPU; convert only at log boundaries.
- **Dtype and device of every tensor entering the model** should be predictable. `dataset.__getitem__` returns CPU tensors; collate stacks them; trainer moves to device before forward.

## Device management

```python
# at script start
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
torch.set_float32_matmul_precision("high")   # TF32 on Ampere+ — free speed

model.to(device)

# in training loop
batch = {k: v.to(device, non_blocking=True) for k, v in batch.items()}
```

- **`non_blocking=True`** on `.to(device)` helps when paired with `pin_memory=True` on the DataLoader. Without pinned memory, `non_blocking=True` is a no-op.
- **Don't move the optimizer** — it's initialized after `model.to(device)`.

## Mixed precision (AMP)

```python
from torch.amp import autocast, GradScaler

scaler = GradScaler()

for batch in loader:
    optimizer.zero_grad(set_to_none=True)
    with autocast(device_type="cuda", dtype=torch.bfloat16):  # or float16
        logits = model(batch.inputs)
        loss = criterion(logits, batch.labels)
    scaler.scale(loss).backward()
    scaler.step(optimizer)
    scaler.update()
```

- **bfloat16** on Ampere (A100) / Ada (4090) / Hopper (H100) — wider dynamic range, no GradScaler needed. Prefer.
- **float16** on older hardware — needs GradScaler to prevent underflow.
- **Don't autocast everything.** Loss + optimizer stays in fp32.

## Training loop — the defensive version

```python
for epoch in range(num_epochs):
    model.train()
    for step, batch in enumerate(train_loader):
        batch = move_to_device(batch, device)

        optimizer.zero_grad(set_to_none=True)   # set_to_none saves memory + is faster
        with autocast(device_type="cuda", dtype=torch.bfloat16):
            outputs = model(**batch)
            loss = outputs.loss / grad_accum_steps

        loss.backward()

        if (step + 1) % grad_accum_steps == 0:
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
            optimizer.step()
            scheduler.step()
            optimizer.zero_grad(set_to_none=True)

        if step % log_interval == 0:
            logger.log({
                "loss": loss.item() * grad_accum_steps,
                "lr": scheduler.get_last_lr()[0],
                "grad_norm": grad_norm,
                "gpu_mem": torch.cuda.max_memory_allocated() / 1e9,
            }, step=global_step)
```

Key points:

- `set_to_none=True` in `zero_grad` — cheaper than setting to zero.
- Gradient accumulation: scale loss by `grad_accum_steps`; only step optimizer every N mini-batches.
- `clip_grad_norm_` before `optimizer.step()`; after `scaler.unscale_(optimizer)` if using GradScaler.
- `model.train()` / `model.eval()` — toggle for dropout + batchnorm behavior; forget and eval looks great then prod loses N points.

## Evaluation — what goes wrong

- Forgetting `model.eval()` → BatchNorm and Dropout still training.
- Forgetting `torch.no_grad()` → memory explodes because activations stay for backward.
- Aggregating metrics per-batch and averaging "average of averages" != global mean.

```python
@torch.no_grad()
def evaluate(model, loader, device):
    model.eval()
    total_loss, total_samples = 0.0, 0
    for batch in loader:
        batch = move_to_device(batch, device)
        outputs = model(**batch)
        total_loss += outputs.loss.item() * batch.batch_size
        total_samples += batch.batch_size
    return total_loss / total_samples
```

## DataLoader

- **`num_workers > 0`** — but **not too high**. Typical: 4-8. Too high = fork/spawn overhead; stalls.
- **`pin_memory=True`** with CUDA — enables faster host→device transfer.
- **`persistent_workers=True`** — avoids worker respawn per epoch.
- **`shuffle=True`** on train; `False` on val/test.
- **`drop_last=True`** on train if BatchNorm is fussy about small final batches.
- **`prefetch_factor=2`** (default) — raise if loader is I/O-bound and you have RAM.

Common footguns:

- **`num_workers=N` + global resources in `Dataset.__init__`** — each worker forks and reinitializes. Don't open a DB connection in `__init__` — open lazily per-worker.
- **Random augmentations with global seed** — all workers produce the same augmentations. Use `worker_init_fn` or `torch.utils.data.get_worker_info()`.
- **Lambda in `Dataset.transform`** — breaks pickling for multi-worker loader. Use a class or module-level function.

## `torch.compile` — free speedup (often)

```python
model = torch.compile(model, mode="default")  # or "reduce-overhead", "max-autotune"
```

- First iteration is slow (graph capture + codegen).
- Subsequent iterations can be 1.3-2× faster.
- **Disable for debugging**: `TORCH_COMPILE_DISABLE=1`.
- Not every model benefits. Profile before assuming a win.
- Dynamic shapes can cause recompiles; try `dynamic=True` or fix shape.

## Distributed training

### DDP (DistributedDataParallel) — the default

```python
torchrun --nproc_per_node=8 train.py
```

- Wrap model: `model = DDP(model, device_ids=[local_rank])`.
- Use `DistributedSampler` on train loader with `.set_epoch(epoch)` every epoch.
- Call `all_reduce` for metric aggregation across ranks.

### FSDP (Fully Sharded Data Parallel) — for large models

When the model doesn't fit on one GPU:

- Shards parameters, gradients, and optimizer state across GPUs.
- `torch.distributed.fsdp.FullyShardedDataParallel` (FSDP2 is the modern path).
- Typically used with `bfloat16`, `torch.compile`, gradient checkpointing.

### HF `accelerate` — the easy button

```bash
accelerate config      # one-time
accelerate launch train.py
```

Handles device placement, DDP/FSDP/DeepSpeed choice, mixed precision. Good default for training pipelines; wraps the boilerplate.

### PyTorch Lightning

Higher-level abstraction (LightningModule, Trainer). Reduces boilerplate; some teams love it, some find it too much magic. Not wrong — just a taste choice. If the codebase already uses it, keep to conventions; if starting fresh, vanilla PyTorch + accelerate is often simpler.

## Memory management

- **Gradient checkpointing** (`torch.utils.checkpoint.checkpoint`) — trades compute for memory; recompute activations in backward. For huge models, often necessary.
- **Lower batch size + gradient accumulation** as first knob.
- **Mixed precision** — roughly halves memory.
- **FSDP** when single-GPU can't fit the model even at small batch.
- **`torch.cuda.empty_cache()`** rarely helps; usually a sign of a leak.

## Saving and loading

```python
torch.save({
    "model": model.state_dict(),          # NOT the whole model object
    "optimizer": optimizer.state_dict(),
    "scheduler": scheduler.state_dict(),
    "epoch": epoch,
    "global_step": global_step,
}, "checkpoint.pt")
```

- Save `state_dict`, not the model. Survives class refactors.
- For DDP/FSDP: save only on rank 0 (`if rank == 0:`). `barrier()` after to sync.
- **safetensors** (`safetensors.torch.save_file`) for shippable weights — safer than pickle-based `.pt`.

## Reproducibility

```python
def set_seed(seed: int):
    import random, numpy as np, torch
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    torch.cuda.manual_seed_all(seed)
    torch.backends.cudnn.deterministic = True    # reproducible, slower
    torch.backends.cudnn.benchmark = False       # true reproducibility
```

Note: fully deterministic CUDA operations aren't always possible (some ops). `torch.use_deterministic_algorithms(True)` raises if an op has no deterministic implementation.

## Do not

- Do not hard-code `.cuda()`. Use `.to(device)`.
- Do not forget `model.eval()` and `torch.no_grad()` in evaluation.
- Do not call `.item()` or `.cpu()` per-step in hot loops.
- Do not save the model object; save `state_dict`.
- Do not use `DataParallel` — it's legacy. `DistributedDataParallel` even for single-machine multi-GPU.
- Do not pickle trained weights for distribution — use safetensors.
- Do not leave `torch.backends.cudnn.benchmark = True` when you need reproducibility.
- Do not mix `torch.compile` with cryptic model code and then blame the compiler. Simplify, then compile.
- Do not set `num_workers` higher than the CPU cores dedicated to your job / the I/O bandwidth supports.
