import 'package:nexgen_command/features/design/manual_editor/pixel_design_document.dart';

/// Design Studio Slice 4 — in-memory undo/redo over immutable
/// [PixelDesignDocument] snapshots (session-scoped). Pushing a new state after
/// an undo truncates the redo tail. History is capped so a long session can't
/// grow unbounded. Pure — no I/O.
class EditHistory {
  final List<PixelDesignDocument> _stack;
  int _cursor;
  final int maxDepth;

  EditHistory(PixelDesignDocument initial, {this.maxDepth = 100})
      : _stack = [initial],
        _cursor = 0;

  PixelDesignDocument get current => _stack[_cursor];
  bool get canUndo => _cursor > 0;
  bool get canRedo => _cursor < _stack.length - 1;
  int get depth => _stack.length;

  /// Records a new state as the current head, dropping any redo tail.
  void push(PixelDesignDocument doc) {
    if (_cursor < _stack.length - 1) {
      _stack.removeRange(_cursor + 1, _stack.length);
    }
    _stack.add(doc);
    if (_stack.length > maxDepth) {
      _stack.removeAt(0); // drop the oldest; keep the window
    }
    _cursor = _stack.length - 1;
  }

  PixelDesignDocument undo() {
    if (canUndo) _cursor--;
    return current;
  }

  PixelDesignDocument redo() {
    if (canRedo) _cursor++;
    return current;
  }
}
