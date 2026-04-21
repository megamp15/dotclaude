---
source: stacks/pytorch
name: pytorch-training-loop
description: The defensive template for a PyTorch training loop — AMP, gradient accumulation, clip, scheduler, checkpoint, metrics. Load when writing or reviewing a training script.
triggers: training loop, model.train, backward, optimizer.step, gradscaler, autocast, gradient accumulation, clip_grad_norm, checkpoint, save state_dict
globs: ["**/train.py", "**/training/*.py", "**/scripts/train*.py", "**/*trainer*.py", "**/*training*.py"]
---

# Training loop — the defensive template

A training loop is easy to write and easy to write subtly wrong. This
is the reference shape; deviations need a reason.

```python
import torch
from torch.amp import autocast, GradScaler

def train_one_epoch(
    model,
    loader,
    optimizer,
    scheduler,
    criterion,
    device,
    *,
    epoch: int,
    global_step: int,
    grad_accum_steps: int = 1,
    max_grad_norm: float = 1.0,
    log_interval: int = 50,
    scaler: GradScaler | None = None,
    logger=None,
) -> int:
    model.train()
    optimizer.zero_grad(set_to_none=True)

    for step, batch in enumerate(loader):
        batch = {k: v.to(device, non_blocking=True) for k, v in batch.items()}

        with autocast(device_type=device.type, dtype=torch.bfloat16, enabled=True):
            outputs = model(**batch)
            loss = outputs.loss / grad_accum_steps

        if scaler is not None:
            scaler.scale(loss).backward()
        else:
            loss.backward()

        is_sync_step = (step + 1) % grad_accum_steps == 0
        if is_sync_step:
            if scaler is not None:
                scaler.unscale_(optimizer)
            grad_norm = torch.nn.utils.clip_grad_norm_(
                model.parameters(), max_norm=max_grad_norm
            )

            if scaler is not None:
                scaler.step(optimizer)
                scaler.update()
            else:
                optimizer.step()

            scheduler.step()
            optimizer.zero_grad(set_to_none=True)
            global_step += 1

            if logger and global_step % log_interval == 0:
                logger.log({
                    "train/loss": loss.item() * grad_accum_steps,
                    "train/lr": scheduler.get_last_lr()[0],
                    "train/grad_norm": grad_norm.item(),
                    "train/gpu_mem_gb": torch.cuda.max_memory_allocated() / 1e9
                        if device.type == "cuda" else 0.0,
                    "epoch": epoch,
                }, step=global_step)

    return global_step
```

## Points to be explicit about

### `zero_grad(set_to_none=True)`

Cheaper (allocates nothing) + plays well with optimizers that check for `None` gradients. Always use it unless you have a specific reason otherwise.

### Loss scaling for accumulation

`loss = outputs.loss / grad_accum_steps`

The gradients accumulate across `grad_accum_steps` mini-batches. Dividing the loss pre-backward keeps the effective gradient the same as a single large batch. Log `loss.item() * grad_accum_steps` so the metric reflects per-batch loss.

### GradScaler + fp16 vs bfloat16

- **bfloat16**: no scaler needed. `autocast(dtype=torch.bfloat16)` with `scaler=None`. Works on Ampere (A100, 3090, 4090) and newer.
- **float16**: needs GradScaler to avoid underflow. Instantiate `scaler = GradScaler()` at top, use the `if scaler is not None:` branch.

Default to bfloat16 on modern GPUs; reach for float16 only on pre-Ampere hardware (V100, T4, 2080Ti).

### Clip before step, not after

`clip_grad_norm_` before `optimizer.step()`. If using GradScaler, `scaler.unscale_(optimizer)` before clip (scaler's scaled gradients need un-scaling to clip meaningfully).

### Step the scheduler per-sync-step, not per-batch

When doing gradient accumulation, scheduler should step with the optimizer — once per effective batch, not once per mini-batch. `scheduler.step()` inside `if is_sync_step:`.

### `global_step` tracking

Metrics should log against the number of *optimizer steps*, not mini-batches. `global_step` increments only when the optimizer steps. This keeps LR schedules, checkpoint cadence, and comparisons across `grad_accum_steps` values consistent.

## Checkpointing discipline

```python
def save_checkpoint(path, *, model, optimizer, scheduler, scaler=None, **extras):
    state = {
        "model": model.state_dict(),
        "optimizer": optimizer.state_dict(),
        "scheduler": scheduler.state_dict(),
        **extras,
    }
    if scaler is not None:
        state["scaler"] = scaler.state_dict()
    torch.save(state, path)

def load_checkpoint(path, *, model, optimizer=None, scheduler=None, scaler=None,
                   map_location=None):
    state = torch.load(path, map_location=map_location, weights_only=True)
    model.load_state_dict(state["model"])
    if optimizer is not None: optimizer.load_state_dict(state["optimizer"])
    if scheduler is not None: scheduler.load_state_dict(state["scheduler"])
    if scaler is not None and "scaler" in state: scaler.load_state_dict(state["scaler"])
    return {k: v for k, v in state.items() if k not in {"model", "optimizer", "scheduler", "scaler"}}
```

- **`weights_only=True`** (PyTorch 2.4+) — safer load; rejects arbitrary Python objects. Use unless you specifically need legacy format.
- **`state_dict`, not whole model.** Survives class refactors; portable.
- **Save optimizer + scheduler + scaler state.** Otherwise resume-from-checkpoint is not actually resuming — LR is wrong, momentum is wrong, scale is wrong.
- **In DDP/FSDP**: gather state to rank 0 and save there. Use `model.module.state_dict()` (unwrap DDP) or `FSDP.state_dict_type(...)` context.

## Common loop bugs (fast triage)

| Symptom | Likely cause |
|---|---|
| Loss NaN immediately | Learning rate too high, or fp16 without scaler, or bad data preprocessing |
| Loss NaN after N steps | Gradient explosion — add / lower `clip_grad_norm_`; consider bfloat16 over fp16 |
| Memory grows each iteration | Retaining tensors with `requires_grad` outside the loop (logging, accumulators). Detach + `.item()` at log sites. |
| Eval loss much higher than train | Forgot `model.eval()` → BN/Dropout still training; or distribution shift |
| Loss won't go down | `optimizer.zero_grad()` missing, or `.backward()` on wrong variable, or model parameters not registered (nn.Parameter) |
| Throughput << expected | Dataloader bottleneck → check `num_workers`, `pin_memory`, `persistent_workers`; or fp32 when bf16 would do |
| Distributed run: one rank slow | Non-uniform data on that rank, or I/O hot-spot on that rank's dataset shard |
| `torch.compile` first step slow | Expected — graph capture + codegen. Runs 2-N should be fast |

## Anti-patterns to reject in review

- **`loss.backward(retain_graph=True)`** without a specific reason (second backward through same graph). Usually a symptom of misunderstanding autograd.
- **`.data` access** on tensors — bypasses autograd. Rarely correct; usually a workaround for confusion.
- **Per-step `.cpu()` or `.numpy()`** for logging inside the training loop.
- **`for p in model.parameters(): p.grad.zero_()`** — use `optimizer.zero_grad(set_to_none=True)`.
- **`optimizer.step()` then `scheduler.step()` then `optimizer.zero_grad()`** — fine order, but placing `zero_grad` at the top of next iteration is equally valid and saves a line.
- **Tracking metrics by appending to a Python list in a GPU-residency-heavy loop** — list holds tensor references; memory leaks across epochs if you don't `.item()`.
- **`torch.save(model, path)`** — save `state_dict`.

## Eval loop companion

```python
@torch.no_grad()
def evaluate(model, loader, criterion, device) -> dict[str, float]:
    model.eval()
    total_loss, total_correct, total_samples = 0.0, 0, 0
    for batch in loader:
        batch = {k: v.to(device, non_blocking=True) for k, v in batch.items()}
        with autocast(device_type=device.type, dtype=torch.bfloat16):
            outputs = model(**batch)
        total_loss += outputs.loss.item() * batch["input_ids"].size(0)
        total_correct += (outputs.logits.argmax(-1) == batch["labels"]).sum().item()
        total_samples += batch["input_ids"].size(0)
    return {
        "eval/loss": total_loss / total_samples,
        "eval/acc": total_correct / total_samples,
    }
```

- `@torch.no_grad()` decorator — no activations kept for backward.
- `model.eval()` at the top.
- Accumulate in floats; avoid computing running means on tensors for this.
- Return a dict of metrics; log at the caller.
