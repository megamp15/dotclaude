# Async and tokio

Async Rust is dominated by tokio in 2026. Most async code, axum, sqlx,
reqwest, hyper are tokio-based. async-std exists but has lost mindshare.
Smol/embassy are niche (embedded, lightweight).

## The runtime

```rust
#[tokio::main(flavor = "multi_thread", worker_threads = 4)]
async fn main() -> anyhow::Result<()> {
    server::run().await
}
```

`flavor = "current_thread"` for a single-thread runtime — useful for
embedded, WASM, tests. Default is multi-threaded.

```rust
#[tokio::main(flavor = "current_thread")]
async fn main() { … }
```

You can also build runtimes manually:

```rust
let rt = tokio::runtime::Builder::new_multi_thread()
    .worker_threads(4)
    .enable_all()
    .build()?;
rt.block_on(async { server::run().await })?;
```

`enable_all()` turns on the IO and time drivers — needed for almost
anything real.

## `tokio::spawn`

Fire-and-forget background task:

```rust
let handle = tokio::spawn(async move {
    work(input).await
});

let result = handle.await?;       // join + propagate panics
```

The future passed to `spawn` must be `Send + 'static`. `'static` because
the runtime owns it. `Send` because it might move between threads.

If the future captures non-`Send` data (e.g. a `Rc`, `RefCell`, raw
pointer), you'll get a long compiler error. Solutions:

- Replace `Rc` with `Arc`.
- Replace `RefCell` with `Mutex` (or move ownership).
- Use `spawn_blocking` for sync-flavor work.
- Use `spawn_local` on a `LocalSet` (current-thread runtime, no `Send`
  required).

## Holding state across `.await`

The single most common async bug:

```rust
let mut guard = state.lock().unwrap();         // std::sync::Mutex
guard.value += 1;
some_async_op().await;                         // BUG: holding lock across await
guard.other += 1;
```

The compiler sometimes catches this (lint `await_holding_lock`) but
not always. Two fixes:

1. **Drop the guard before `.await`:**
   ```rust
   {
       let mut guard = state.lock().unwrap();
       guard.value += 1;
   }
   some_async_op().await;
   {
       let mut guard = state.lock().unwrap();
       guard.other += 1;
   }
   ```

2. **Use `tokio::sync::Mutex`** if you genuinely need to hold the lock
   across `.await`:
   ```rust
   let mut guard = state.lock().await;        // tokio::sync::Mutex
   guard.value += 1;
   some_async_op().await;                     // OK — guard supports yield
   ```

`tokio::sync::Mutex` is ~10× slower than `std::sync::Mutex` (or
`parking_lot::Mutex`). Default to the std one and structure code to not
hold across `.await`.

## `select!` and cancellation safety

Race two futures, take whichever completes first:

```rust
tokio::select! {
    res = recv_message() => { handle(res) }
    _ = tokio::time::sleep(Duration::from_secs(5)) => { return Err(Timeout) }
}
```

The future that didn't complete is **dropped mid-execution**. This is
"cancellation". Some futures are *cancellation-safe* (re-entering
produces the same effect); others are not.

| Cancellation-safe | Not cancellation-safe |
|---|---|
| `tokio::time::sleep` | `tokio::io::AsyncReadExt::read_to_end` |
| `tokio::sync::mpsc::Receiver::recv` | Any future that mutates external state mid-await |
| `Notify::notified` | A custom future that's holding a partial transaction |

The docs for each tokio API state cancellation safety. Read carefully
when using `select!`.

If a future isn't cancellation-safe, race against `JoinHandle` instead
of polling directly:

```rust
let handle = tokio::spawn(unsafe_future());
tokio::select! {
    res = &mut handle => { … }
    _ = sleep(timeout) => { handle.abort(); … }
}
```

## Structured concurrency: `JoinSet`

Spawn N tasks, await all results, abort all on drop:

```rust
let mut set = tokio::task::JoinSet::new();
for url in urls {
    set.spawn(fetch(url));
}
let mut results = vec![];
while let Some(res) = set.join_next().await {
    results.push(res??);
}
```

`JoinSet` aborts pending tasks when dropped. Cleaner than juggling
`Vec<JoinHandle>`. Bound concurrency with a counted approach:

```rust
let semaphore = Arc::new(Semaphore::new(8));
for url in urls {
    let permit = semaphore.clone().acquire_owned().await?;
    set.spawn(async move {
        let _permit = permit;       // dropped when task finishes
        fetch(url).await
    });
}
```

## `spawn_blocking`

For CPU-heavy or blocking-IO work that mustn't tie up the async runtime:

```rust
let result = tokio::task::spawn_blocking(move || {
    expensive_sync_computation(input)
}).await?;
```

This runs on a separate thread pool (default 512 threads). Use for:

- Heavy CPU work (image encoding, crypto).
- Calling sync libraries (`std::fs` if you want sync semantics; `rusqlite`).
- Long-running CPU loops in async context.

`block_in_place` is a less-isolated alternative — runs on the current
worker thread but moves other work off it. Rare; use `spawn_blocking`
unless you have a measured reason.

## Async traits

Rust 1.75+ supports `async fn` directly in traits:

```rust
trait Storage {
    async fn get(&self, key: &str) -> Result<Vec<u8>>;
    async fn put(&self, key: &str, value: Vec<u8>) -> Result<()>;
}
```

This works for `impl Storage` static dispatch. For dynamic dispatch
(`Box<dyn Storage>`), you need `async-trait`:

```rust
#[async_trait::async_trait]
trait Storage {
    async fn get(&self, key: &str) -> Result<Vec<u8>>;
    async fn put(&self, key: &str, value: Vec<u8>) -> Result<()>;
}
```

`async-trait` boxes the future (allocation per call). Default to native
`async fn` and only switch when you need object safety.

## Channels

| Channel | Use when |
|---|---|
| `tokio::sync::mpsc` | Multiple producers, one consumer. The default. |
| `tokio::sync::oneshot` | Single-shot reply channel. RPC-shaped patterns. |
| `tokio::sync::broadcast` | Multiple consumers, all see all values. Pub/sub. |
| `tokio::sync::watch` | Latest-value broadcast. Config updates, latest state. |
| `flume` (third-party) | When you need both sync and async senders. |

```rust
let (tx, mut rx) = tokio::sync::mpsc::channel::<Message>(32);

tokio::spawn(async move {
    while let Some(msg) = rx.recv().await {
        handle(msg).await;
    }
});

tx.send(message).await?;
```

Bounded channels apply backpressure (sender awaits when full); unbounded
channels are an unbounded queue (avoid). The buffer size is a tuning
knob — start with 32 or so.

## Common pitfalls

- **`std::thread::sleep` in async code.** Blocks the worker thread. Use
  `tokio::time::sleep`.
- **`std::fs::*` in async code.** Same — blocks. Use `tokio::fs::*` or
  `spawn_blocking`.
- **Calling `.await` inside a `Mutex` guard from `std::sync`.** See
  above. Drop the guard or use tokio's mutex.
- **CPU loop in async fn.** A 200ms-busy `async fn` blocks the worker.
  Move to `spawn_blocking`.
- **`futures::join!` instead of `tokio::join!`.** They have subtly
  different semantics; tokio's is the right default in tokio code.
- **Forgetting `.await`.** A Future that's never polled does nothing.
  Clippy warns (`must_use`).
- **`async fn` returning a non-`Send` future** that gets passed to
  `tokio::spawn`. Long error message; the fix is to make the captured
  state `Send`.

## Diagnostics

- **`tokio-console`** — runtime introspection (active tasks, locks,
  resources). `RUSTFLAGS="--cfg tokio_unstable"` and add the
  `console-subscriber` crate.
- **`tracing`** crate with `tracing-subscriber` — structured logging
  with span hierarchy. The async-aware version of `log`.
- **`#[tokio::test]`** — automatically wraps a test in a tokio runtime.
- **`#[tokio::test(flavor = "multi_thread", worker_threads = 4)]`** —
  for tests that need true concurrency.
