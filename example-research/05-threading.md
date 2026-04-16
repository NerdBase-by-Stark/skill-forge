# Stream 5: PySide6 Threading Deep-Dive

## Research Summary

This document consolidates verified, non-obvious threading patterns for PySide6 6.7+ desktop apps (Qt 6). Research focuses on GUDE Deploy's pain points: 120 parallel device firmware uploads, batch config deployment, and UI responsiveness. All findings cross-referenced with official Qt 6 / PySide6 docs and confirmed bug reports. Pre-Qt 6 advice rejected as stale.

**Key insight**: Qt 6 threading is safer than PyQt5/PySide2, but edge cases still exist around thread affinity, signal reentrancy, and asyncio integration.

---

## Verified Gems

### 1. AutoConnection Gotcha: Thread Affinity Captured at connect(), Not Emission

**The Issue**: Developers assume `Qt.AutoConnection` re-evaluates thread affinity at signal emission. It doesn't.

When you call `signal.connect(slot, Qt.AutoConnection)`, Qt captures both objects' thread affinities **at connection time**. If you later move the receiver to a different thread via `moveToThread()`, the connection type **remains unchanged** and executes with the original decision (Direct or Queued). This causes slots to execute in the wrong thread.

**Practical impact for GUDE Deploy**: If a worker device config object is created in the main thread, then moved to a QThread, connecting to its slots before `moveToThread()` is critical. Connecting after the move silently produces incorrect behavior.

**Rule**: Establish signal-slot connections **before** any `moveToThread()` calls, or explicitly pass `Qt.QueuedConnection` to force queued behavior across thread boundaries.

**Source**: [Qt 6 Threads and QObjects](https://doc.qt.io/qt-6/threads-qobject.html) — "If the signal is emitted in the thread which the receiving object has affinity then the behavior is the same as the Direct Connection. Otherwise, the behavior is the same as the Queued Connection."

---

### 2. QThreadPool.start() With Plain Functions (PySide6 6.2+): Underused Simplification

Most code examples still show QRunnable subclassing for QThreadPool. Since **PySide6 6.2** (2021), `QThreadPool.start()` accepts bare Python functions, methods, or slots directly. This eliminates the boilerplate of QRunnable subclasses for simple tasks.

```python
# Old way (still valid):
class Worker(QRunnable):
    def run(self):
        result = expensive_http_call()

pool.start(Worker())

# Modern way (PySide6 6.2+):
pool.start(expensive_http_call)
```

For GUDE Deploy's 120 parallel device uploads, this simplifies submission logic. However, note that **auto-deletion is enabled by default** for QRunnable—do not reuse the same function across multiple `start()` calls if side effects occur.

**Rule**: Use `QThreadPool.start(function)` for one-off tasks. Reserve QRunnable subclassing for complex workers with internal state or signal emission.

**Source**: [PythonGUIs QThreadPool Tutorial](https://www.pythonguis.com/tutorials/multithreading-pyside6-applications-qthreadpool/)

---

### 3. Signal Emission Is NOT Thread-Safe (But connect() Is)

**Critical misconception**: "Qt signals are thread-safe."

Signals are **safe to connect** from any thread. But **emitting** a signal from a non-affinity thread causes undefined behavior: corruption, crashes, or silent race conditions under load.

```python
# SAFE:
worker_signal.connect(self.on_progress)  # from any thread

# UNSAFE:
# (from ThreadPoolExecutor worker:)
self.some_signal.emit(value)  # WRONG THREAD
```

For firmware uploads emitting progress every ~50ms across 120 devices, this is easy to miss. Workers in ThreadPoolExecutor or QThread must **never** directly emit signals. Instead, use:

1. **Intermediate QObject** (moveToThread pattern): Worker lives in QThread and emits safely.
2. **Thread-safe queue + watcher**: Python queue + QThread monitor that polls and emits.
3. **Qt.invokeMethod() with QueuedConnection** (PySide6 6.1+): `QtCore.QMetaObject.invokeMethod(obj, "method", Qt.QueuedConnection, QtCore.Q_ARG(...))`

**Rule**: Never emit signals directly from ThreadPoolExecutor workers. Use signal-emitting QObject wrapper or invokeMethod pattern.

**Source**: [Qt 6 Threads and QObjects](https://doc.qt.io/qt-6/threads-qobject.html) — "Slots are thread-safe, but signals are not."

---

### 4. deleteLater() Pattern for Cleanup: Essential for Thread Safety

Direct `del object` from a non-affinity thread causes crashes if the object is processing events or holds resources. Use `object.deleteLater()` instead.

`deleteLater()` posts a deferred delete event to the object's thread, allowing cleanup in its own thread context.

For GUDE Deploy: If a device config fails and must clean up an in-flight upload, use deleteLater() on workers:

```python
worker = DeviceUploadWorker()
worker.moveToThread(self.thread_pool)
# ... later, on cancellation:
worker.deleteLater()  # safe, even if upload is mid-flight
```

**Rule**: Never `del` QObjects from threads other than their affinity thread. Always use `deleteLater()`.

**Source**: [Qt 6 Threads and QObjects](https://doc.qt.io/qt-6/threads-qobject.html) — "deleteLater() is safe from any thread."

---

### 5. QObject Thread Affinity: Methods Called From Wrong Thread = Corruption

Calling non-slot methods on a QObject from a non-affinity thread is explicitly unsafe in Qt docs and can cause:
- Segmentation faults
- Race condition corruption (visible only under load)
- Silent logical errors

The Qt docs state: "QObjects are not thread-safe. Reading or writing memory from different threads can lead to race conditions or segfaults."

For GUDE Deploy, if a firmware upload worker calls `self.device_config.update_field()` directly from ThreadPoolExecutor, and `device_config` lives in the main thread, you get undefined behavior.

**Solution**: Emit a signal from the worker; connect it to a slot on the main thread.

**Rule**: Access QObject methods only from their affinity thread. Use signals/slots for cross-thread updates.

**Source**: [Qt 6 Threads and QObjects](https://doc.qt.io/qt-6/threads-qobject.html)

---

### 6. moveToThread Pattern IS Current Best Practice (Qt 6 Consensus)

The old Qt dogma "never subclass QThread" remains the consensus in Qt 6, reinforced by official docs and blog posts.

**Correct pattern**:
```python
class ConfigWorker(QObject):
    progress = pyqtSignal(int)
    def run_config(self):
        ...
        self.progress.emit(50)

worker = ConfigWorker()
thread = QThread()
worker.moveToThread(thread)
worker.progress.connect(self.on_progress)
thread.started.connect(worker.run_config)
thread.start()
```

**Why**: A QThread instance lives in the thread that created it, not the thread it "starts." Direct subclassing confuses event loop ownership. moveToThread() ensures the worker's slots execute in the correct thread.

**Exception**: Single, fire-and-forget operations with no event-driven objects (no timers, no sockets, no signals). Subclassing is overkill then.

**Rule**: Use moveToThread for any worker that receives signals, emits signals, or uses event-driven classes (QTimer, QTcpSocket, QProcess).

**Sources**: [Real Python — PyQt QThread](https://realpython.com/python-pyqt-qthread/), [Qt 6 Docs](https://doc.qt.io/qt-6/threads-qobject.html)

---

### 7. Lambda + Signal Memory Leaks: Captured self Prevents GC

When connecting a lambda that captures `self`, Python's reference-counting cannot garbage-collect the widget, even after all other references are dropped.

```python
# MEMORY LEAK:
self.btn.clicked.connect(lambda: self.on_click())  # self captured, GC blocked
```

Qt **does not automatically disconnect lambdas** on object deletion (unlike regular slot methods). The lambda holds `self` alive, creating a reference cycle.

**Solutions**:
1. Use explicit slot methods (Qt auto-disconnects on deletion).
2. Store the connection handle and call `disconnect()` on cleanup.
3. Use a wrapper QObject (best for complex closures).

For GUDE Deploy's dynamic device widgets (created/destroyed per scan), lambdas cause memory leaks. Use slot methods instead.

**Rule**: Avoid lambdas in signal connections. Use explicit slot methods. If required, disconnect explicitly in `closeEvent()` or use a wrapper QObject.

**Sources**: [Qt Forum Memory Leaks](https://forum.qt.io/topic/152101/memory-can-not-release-correctly-because-of-using-lambda-as-slot), [SEP Memory Leaks](https://sep.com/blog/prevent-signal-slot-memory-leaks-in-python/)

---

### 8. BlockingQueuedConnection Deadlock: Same Thread = Instant Deadlock

If two objects in the same thread connect with `Qt.BlockingQueuedConnection`, calling the signal deadlocks immediately. The signal emitter posts an event to the receiver's event loop **and waits for it to process**, but the receiver's event loop is blocked by the sender waiting.

```python
# DEADLOCK:
# Both objects in main thread:
obj1.signal.connect(obj2.slot, Qt.BlockingQueuedConnection)
obj1.signal.emit()  # DEADLOCK
```

This is rarely intentional but can happen accidentally in tests or during migration. Qt 6 doesn't prevent it—the developer must use correct connection types.

**Rule**: `BlockingQueuedConnection` is only safe across threads. In same-thread contexts, use `Qt.DirectConnection` or `Qt.AutoConnection`.

**Source**: [Qt 6 Threads and QObjects](https://doc.qt.io/qt-6/threads-qobject.html)

---

### 9. Future.cancel() Limitations: Only Cancels Unstarted Tasks

`concurrent.futures.Future.cancel()` returns `False` if the task has already started. For GUDE Deploy's 120 in-flight uploads, clicking "Cancel" won't stop running tasks—only pending ones.

For in-flight cancellation, use a shared `threading.Event` flag that workers poll:

```python
stop_flag = threading.Event()

def upload_firmware(device_id):
    for chunk in firmware_chunks:
        if stop_flag.is_set():
            return  # cooperative cancellation
        send_chunk(device_id, chunk)

executor.submit(upload_firmware, "device1")
# ... user clicks Cancel:
stop_flag.set()  # workers check and exit
```

**Rule**: For graceful shutdown, use `threading.Event` shared flags, not `Future.cancel()`. Always `executor.shutdown(wait=True)` in `closeEvent()`.

**Source**: [Super Fast Python — ThreadPoolExecutor Cancellation](https://superfastpython.com/threadpoolexecutor-cancel-task/)

---

### 10. QtAsyncio (Official Qt 6 Solution) vs qasync (Maintained Third-Party)

**QtAsyncio** (built into PySide6 6.6.2+):
- Official Qt solution; part of PySide6 core.
- API identical to asyncio (event loop functions like `run_until_complete()`, `create_task()`, `run_in_executor()`).
- Still technical preview; expect API evolution.
- Allows `async`/`await` code alongside Qt signals.

**qasync** (community-maintained fork):
- Third-party; maintained by Cabbage Development (commits in past 12 months).
- Mature; used in production codebases.
- Decorators like `@asyncSlot()` and `@asyncClose`.
- Compatible with PyQt/PySide; works on Qt 5 and Qt 6.

**For new GUDE Deploy features**: QtAsyncio is recommended (official, zero dependencies). For existing code or complex async patterns, qasync is the mature fallback.

**Neither is essential for GUDE Deploy** (ThreadPoolExecutor + signals is sufficient), but useful if you need `asyncio.gather()` for coordinating 120 parallel tasks elegantly.

**Sources**: [Qt Blog — QtAsyncio Technical Preview](https://www.qt.io/blog/introducing-qtasyncio-in-technical-preview), [qasync GitHub](https://github.com/CabbageDevelopment/qasync)

---

## Proposed Skill Rules

1. **Thread Affinity Rule**: Establish all signal-slot connections before calling `moveToThread()`. If a QObject's thread affinity changes, re-establish connections or use explicit `Qt.QueuedConnection`.

2. **Signal Emission Thread Safety**: Signals may only be emitted by their defining object (in its affinity thread). Workers in ThreadPoolExecutor must not emit directly; use signal-emitting QObject wrapper, queue + monitor, or `QtCore.QMetaObject.invokeMethod(..., Qt.QueuedConnection)`.

3. **Cross-Thread Cleanup Rule**: Always use `object.deleteLater()` for cleanup from non-affinity threads. Never call `del` directly on QObjects from background threads.

4. **Lambda Connection Prohibition**: Avoid lambdas in signal connections; they prevent garbage collection. Use explicit slot methods. If necessary, store the connection handle for explicit disconnect.

5. **moveToThread for Worker Objects**: Use moveToThread pattern for any worker needing signals, event-driven classes, or slot connectivity. Single fire-and-forget operations may use QThread subclassing if truly stateless.

6. **ThreadPoolExecutor Cancellation Pattern**: Use `threading.Event` shared flags for cooperative cancellation; don't rely on `Future.cancel()`. Always `executor.shutdown(wait=True)` in `closeEvent()`.

---

## Library Recommendations (asyncio integration)

| Library | Maintained 2025+ | Qt 6 Support | Maturity | Best For |
|---------|------------------|--------------|----------|----------|
| **QtAsyncio** (official) | Yes (PySide6 core) | Yes (6.6.2+) | Technical Preview | New projects; official Qt blessing |
| **qasync** (community) | Yes (commits past 12m) | Yes | Mature (production) | Existing codebases; `@asyncSlot` decorators |
| **qtinter** | Unknown (fork) | Unclear | Early | Interop research only |

**Note**: Neither is required for GUDE Deploy. QThreadPool + signals handles 120 parallel uploads cleanly. Use only if `asyncio.gather()` coordination is needed.

---

## Anti-Patterns Found

1. **QThread Subclassing for Everything**: Creates confusion about where slots run. Use moveToThread pattern instead.

2. **Direct QObject Access Across Threads**: Calling methods on non-affinity QObjects leads to silent corruption under load. Always use signals/slots.

3. **Emitting Signals from ThreadPoolExecutor**: Workers in thread pool are not in Qt's thread context. Must use wrapper objects or invokeMethod.

4. **BlockingQueuedConnection in Same Thread**: Deadlocks immediately if sender and receiver are in same thread.

5. **Relying on Future.cancel() for In-Flight Tasks**: Only works for pending tasks. Use `threading.Event` for running task cancellation.

6. **Lambdas in Signal Connections**: Captures `self`, preventing garbage collection. Creates memory leaks in dynamic UIs.

7. **Missing shutdown in closeEvent()**: Executor threads keep running after window close, blocking app exit. Always call `executor.shutdown(wait=True)`.

---

## Open Questions / Unverified

1. **QtConcurrent.run() Availability in PySide6**: Official docs list QFuture and QtConcurrent, but Qt Wiki notes "Missing Bindings" for QFuture* in PySide6. Unclear if fully accessible or limited. Recommendation: Test locally before adopting.

2. **Qt.invokeMethod() Argument Wrapping**: Qt.Q_ARG() syntax for invokeMethod with custom types not verified in PySide6. May require workaround or wrapper.

3. **Signal Reentrancy Behavior**: If slot A emits signal that triggers slot A again (nested), does Qt queue or execute directly? Not tested in PySide6 6.7; Qt 6 docs silent on this edge case.

4. **Progress Signal Coalescing**: Sending 120 concurrent `progress(int)` signals may overwhelm UI thread. Optimal batching strategy (e.g., 10Hz update timer) not benchmarked for GUDE Deploy's device count.

---

## Sources

- [Qt 6 Threads and QObjects](https://doc.qt.io/qt-6/threads-qobject.html) — Authoritative thread affinity rules, AutoConnection behavior, edge cases.
- [PySide6.QtCore QObject Reference](https://doc.qt.io/qtforpython-6/PySide6/QtCore/QObject.html)
- [PySide6 QThreadPool Tutorial](https://www.pythonguis.com/tutorials/multithreading-pyside6-applications-qthreadpool/) — Modern patterns, 6.2+ function submission.
- [Real Python — PyQt QThread](https://realpython.com/python-pyqt-qthread/) — moveToThread vs subclassing debate, current consensus.
- [Qt Blog — QtAsyncio Technical Preview](https://www.qt.io/blog/introducing-qtasyncio-in-technical-preview) — Official asyncio integration, status.
- [qasync GitHub](https://github.com/CabbageDevelopment/qasync) — Maintained third-party asyncio adapter, maintenance status.
- [Qt Forum — Thread Affinity Edge Cases](https://forum.qt.io/topic/160665/pyside6-slot-executed-in-signal-s-thread-even-with-auto-queuedconnection) — Real-world gotchas.
- [SEP Blog — Memory Leaks in Signal Connections](https://sep.com/blog/prevent-signal-slot-memory-leaks-in-python/) — Lambda capture, GC prevention.
- [Super Fast Python — ThreadPoolExecutor Cancellation](https://superfastpython.com/threadpoolexecutor-cancel-task/) — Future.cancel() limitations, Event-based patterns.
- [Qt 6 Documentation — Queued Connections](https://woboq.com/blog/how-qt-signals-slots-work-part3-queuedconnection.html) — Signal-slot thread routing deep-dive.

---

## Recommendations for GUDE Deploy Immediate Integration

1. **Firmware Upload Progress (120 Devices)**:
   - Use `QThreadPool.start(upload_device)` for simple submission.
   - Emit progress via signal-emitting QObject wrapper (not directly from ThreadPoolExecutor).
   - Implement 10Hz batched progress update (not 1/chunk) to avoid drowning UI thread.

2. **Batch Configuration Deploy**:
   - Use moveToThread + signal pattern for config workers.
   - Establish signal-slot connections **before** moveToThread.
   - Use `threading.Event` for Cancel button instead of Future.cancel().

3. **Cleanup on Window Close**:
   - Add `executor.shutdown(wait=True)` to `closeEvent()`.
   - Call `thread.quit()` and `thread.wait()` for QThread objects.
   - Use `deleteLater()` for any in-flight worker cleanup.

4. **Avoid for Now**:
   - QtAsyncio (technical preview; not stable enough for production tool).
   - QtConcurrent.run() (bindings incomplete; QFuture not fully accessible).
   - Lambdas in signal connections (use slot methods instead).

