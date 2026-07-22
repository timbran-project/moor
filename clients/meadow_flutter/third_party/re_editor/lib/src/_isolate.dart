part of re_editor;

typedef IsolateRunnable<Req, Res> = Res Function(Req req);
typedef IsolateCallback<Res> = void Function(Res res);

/// Runs tasks synchronously. The original implementation used isolate_manager
/// to offload work to a background isolate/web-worker, but that package
/// depends on dart:html which blocks WASM builds. Syntax highlighting, chunk
/// analysis, and find are fast enough to run on the main thread for typical
/// source files.
class _IsolateTasker<Req, Res> {
  final String name;
  final IsolateRunnable<Req, Res> _runnable;
  bool _closed = false;

  _IsolateTasker(this.name, this._runnable);

  void run(Req req, IsolateCallback<Res> callback) {
    if (_closed) return;
    final result = _runnable(req);
    if (_closed) return;
    callback(result);
  }

  void close() {
    _closed = true;
  }
}
