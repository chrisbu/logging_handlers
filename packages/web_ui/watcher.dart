// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/**
 * A library to observe changes on Dart objects.
 *
 * Similar to the principle of watchers in AngularJS, this library provides the
 * mechanisms to observe and react to changes that happen in an application's
 * data model.
 *
 * Watchers have a simple lifetime:
 *
 *   * they are created calling [watch],
 *
 *   * they are fired whenever [dispatch] is called and the watched values
 *   changed since the last time [dispatch] was invoked, and
 *
 *   * they are unregistered using a function that was returned by [watch] when
 *   they were created.
 *
 * For example, you can create a watcher that observes changes to a variable by
 * calling [watch] as follows:
 *
 *     var x = 0;
 *     var stop = watch(() => x, (_) => print('hi'));
 *
 * Changes to the variable 'x' will be detected whenever we call [dispatch]:
 *
 *     x = 12;
 *     x = 13;
 *     dispatch(); // the watcher is invoked ('hi' will be printed once).
 *
 * After deregistering the watcher, events are no longer fired:
 *
 *     stop();
 *     x = 14;
 *     dispatch(); // nothing happens.
 *
 * You can watch several kinds of expressions, including lists. See [watch] for
 * more details.
 *
 * A common design pattern for MVC applications is to call [dispatch] at the end
 * of each event loop (e.g. after each UI event is fired). Our view library does
 * this automatically.
 */
library watcher;

import 'dart:async';
import 'dart:collection';
import 'observe.dart';
import 'src/linked_list.dart';

/**
 * True to use the [observe] library instead of watchers.
 *
 * Observers require the [observable] annotation on objects and for collection
 * types to be observable, such as [ObservableList]. But in return they offer
 * better performance and more precise change tracking. [dispatch] is not
 * required with observers, and changes to observable objects are always
 * detected.
 *
 * Currently this flag is experimental, but it may be the default in the future.
 */
bool useObservers = false;

/**
 * Watch for changes in [target].  The [callback] function will be called when
 * [dispatch] is called and the value represented by [target] had changed.  The
 * returned function can be used to unregister this watcher.
 *
 * There are several values you can use for [target]:
 *
 *   * A [Getter] function.
 *   Use this to watch expressions as they change. For instance, to watch
 *   whether `a.b.c` changes, wrap it in a getter and call [watch] as follows:
 *         watch(() => a.b.c, ...)
 *   These targets are tracked to check for equality. If calling `target()`
 *   returns the same result, then the [callback] will not be invoked. In the
 *   special case whe the getter returns a [List], we will treat the value in a
 *   special way, similar to passing [List] directly as [target].
 *   **Important**: this library assumes that [Getter] is a read-only function
 *   and that it will consistently return the same value if called multiple
 *   times in a row.
 *
 *   * A [List].
 *   Use this to watch whether a list object changes. For instance, to detect
 *   if an element is added or changed in a list can call [watch] as follows:
 *         watch(list, ...)
 *
 *   * A [Handle].
 *   This is syntactic sugar for using the getter portion of a [Handle].
 *         watch(handle, ...)  // equivalent to `watch(handle._getter, ...)`
 */
ChangeUnobserver watch(target, ChangeObserver callback, [String debugName]) {
  if (useObservers) return observe(target, callback);

  if (callback == null) return () {}; // no use in passing null as a callback.
  if (_watchers == null) _watchers = new LinkedList<_Watcher>();
  Function exp;
  bool isList = false;
  if (target is Handle) {
    exp = (target as Handle)._getter;
  } else if (target is Function) {
    exp = target;
    try {
      var val = target();
      if (val is List) {
        isList = true;
      } else if (val is Iterable) {
        isList = true;
        exp = () => target().toList();
      }
    } catch (e, trace) { // in case target() throws some error
      // TODO(sigmund): use logging instead of print when logger is in the SDK
      // and available via pub (see dartbug.com/4363)
      print('error: evaluating ${debugName != null ? debugName : "<unnamed>"} '
            'watcher threw error ($e, $trace)');
    }
  } else if (target is List) {
    exp = () => target;
    isList = true;
  } else if (target is Iterable) {
    exp = () => target.toList();
    isList = true;
  }
  var watcher = isList
      ? new _ListWatcher(exp, callback, debugName)
      : new _Watcher(exp, callback, debugName);
  var node = _watchers.add(watcher);
  return node.remove;
}

/**
 * Add a watcher for [exp] and immediatly invoke [callback]. The watch event
 * passed to [callback] will have `null` as the old value, and the current
 * evaluation of [exp] as the new value.
 */
ChangeUnobserver watchAndInvoke(exp, callback, [debugName]) {
  var res = watch(exp, callback, debugName);
  // TODO(jmesserly): this should be "is Getter" once dart2js bug is fixed.

  var value = exp;
  if (value is Function) {
    value = value();
  }
  if (value is Iterable && value is! List) {
    // TODO(jmesserly): we do this for compat with watch and observe, see the
    // respective methods.
    value = value.toList();
  }
  callback(new ChangeNotification(null, value));
  return res;
}

/** Internal set of active watchers. */
LinkedList<_Watcher> _watchers;

/**
 * An internal representation of a watcher. Contains the expression it watches,
 * the last value seen for it, and a callback to invoke when a change is
 * detected.
 */
class _Watcher {
  /** Name used to debug. */
  final String debugName;

  /** Function that retrieves the value being watched. */
  final Getter _getter;

  /** Callback to invoke when the value changes. */
  final ChangeObserver _callback;

  /** Last value observed on the matched expression. */
  var _lastValue;

  _Watcher(this._getter, this._callback, this.debugName) {
    _lastValue = _getter();
  }

  String toString() => debugName == null ? '<unnamed>' : debugName;

  /** Detect if any changes occurred and if so invoke [_callback]. */
  bool compareAndNotify() {
    var currentValue = _safeRead();
    if (_compare(currentValue)) {
      var oldValue = _lastValue;
      _update(currentValue);
      _callback(new ChangeNotification(oldValue, currentValue));
      return true;
    }
    return false;
  }

  bool _compare(currentValue) => _lastValue != currentValue;

  void _update(currentValue) {
    _lastValue = currentValue;
  }

  /** Read [_getter] but detect whether exceptions were thrown. */
  _safeRead() {
    try {
      return _getter();
    } catch (e, trace) {
      print('error: evaluating $this watcher threw an exception ($e, $trace)');
    }
    return _lastValue;
  }
}

/** Bound for the [dispatch] algorithm. */
final int _maxIter = 10;

/**
 * Scan all registered watchers and invoke their callbacks if the watched value
 * has changed. Because we allow listeners to modify other watched expressions,
 * [dispatch] will reiterate until no changes occur or until we reach a
 * particular limit (10) to ensure termination.
 */
void dispatch() {
  if (_watchers == null) return;
  bool dirty;
  int total = 0;
  do {
    dirty = false;
    for (var watcher in _watchers) {
      // Get the next node just in case this node gets remove by the watcher
      if (watcher.compareAndNotify()) {
        dirty = true;
      }
    }
  } while (dirty && ++total < _maxIter);
  if (total == _maxIter) {
    print('Possible loop in watchers propagation, stopped dispatch.');
  }
}

/**
 * An indirect getter. Basically a simple closure that returns a value, which is
 * the most common argument in [watch].
 */
typedef T Getter<T>();

/** An indirect setter. */
typedef void Setter<T>(T value);

/**
 * An indirect reference to a value. This is used to create two-way bindings in
 * MVC applications.
 *
 * The model can be a normal Dart class. You can then create a handle to a
 * particular reference so that the view has read/write access without
 * internally revealing your model abstraction. For example, consider a model
 * class containing whether or not an item is 'checked' on a list:
 *
 *     class Item {
 *       int id;
 *       ...
 *       bool checked;
 *
 * Then we can use a CheckBox view and only reveal the status of the checked
 * field as follows:
 *
 *     new CheckBoxView(new Handle<bool>(
 *         () => item.checked,
 *         (v) { item.checked = v}));
 *
 * A handle with no setter is a read-only handle.
 */
class Handle<T> {
  final Getter<T> _getter;
  final Setter<T> _setter;

  /** Create a handle, possibly read-only (if no setter is specified). */
  Handle(this._getter, [this._setter]);

  Handle.of(T value) : this(() => value);

  T get value => _getter();

  void set value(T value) {
    if (_setter != null) {
      _setter(value);
    } else {
      throw new Exception('Sorry - this handle has no setter.');
    }
  }
}

/**
 * A watcher for list objects. It stores as the last value a shallow copy of the
 * list as it was when we last detected any changes.
 */
class _ListWatcher<T> extends _Watcher {

  _ListWatcher(getter, ChangeObserver callback, String debugName)
      : super(getter, callback, debugName) {
    _update(_safeRead());
  }

  bool _compare(List<T> currentValue) {
    if (_lastValue.length != currentValue.length) return true;

    for (int i = 0 ; i < _lastValue.length; i++) {
      if (_lastValue[i] != currentValue[i]) return true;
    }
    return false;
  }

  void _update(currentValue) {
    _lastValue = new List<T>.from(currentValue);
  }
}
