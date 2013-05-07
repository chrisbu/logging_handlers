// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/**
 * This library exports all of the commonly used functions and types for
 * building UI's. It is equivalent to the following imports:
 *
 *     import 'package:web_ui/observe.dart';
 *     import 'package:web_ui/safe_html.dart';
 *     import 'package:web_ui/templating.dart';
 *     import 'package:web_ui/watcher.dart';
 *     import 'package:web_ui/web_ui.dart' show WebComponent;
 *
 * Note that the [WebComponent] base class is defined in this library.
 *
 * See this article for more information:
 * <http://www.dartlang.org/articles/dart-web-components/>.
 */
library web_ui;

export 'observe.dart';
export 'safe_html.dart';
export 'templating.dart';
export 'watcher.dart';

import 'dart:async';
import 'dart:html';
import 'package:meta/meta.dart';

/**
 * The base class for all Dart web components. In addition to the [Element]
 * interface, it also provides lifecycle methods:
 * - [created]
 * - [inserted]
 * - [attributeChanged]
 * - [removed]
 */
abstract class WebComponent implements Element {
  /** The web component element wrapped by this class. */
  Element _host;
  List _shadowRoots;

  /**
   * Temporary property until components extend [Element]. An element can
   * only be associated with one host, and it is an error to use a web component
   * without an associated host element.
   */
  Element get host {
    if (_host == null) throw new StateError('host element has not been set.');
    return _host;
  }

  set host(Element value) {
    if (value == null) {
      throw new ArgumentError('host must not be null.');
    }
    if (value.xtag != null) {
      throw new ArgumentError('host must not have its xtag property set.');
    }
    if (_host != null) {
      throw new StateError('host can only be set once.');
    }

    value.xtag = this;
    _host = value;
  }

  /**
   * **Note**: This is an implementation helper and should not need to be called
   * from your code.
   *
   * Creates the [ShadowRoot] backing this component.
   */
  createShadowRoot() {
    if (_realShadowRoot) {
      return host.createShadowRoot();
    }
    if (_shadowRoots == null) _shadowRoots = [];
    _shadowRoots.add(new DivElement());
    return _shadowRoots.last;
  }

  /**
   * Invoked when this component gets created.
   * Note that [root] will be a [ShadowRoot] if the browser supports Shadow DOM.
   */
  void created() {}

  /** Invoked when this component gets inserted in the DOM tree. */
  void inserted() {}

  /** Invoked when this component is removed from the DOM tree. */
  void removed() {}

  // TODO(jmesserly): how do we implement this efficiently?
  // See https://github.com/dart-lang/web-ui/issues/37
  /** Invoked when any attribute of the component is modified. */
  void attributeChanged(String name, String oldValue, String newValue) {}

  get model => host.model;

  void set model(newModel) {
    host.model = newModel;
  }

  void clearModel() => host.clearModel();

  Stream<Node> get onModelChanged => host.onModelChanged;

  /**
   * **Note**: This is an implementation helper and should not need to be called
   * from your code.
   *
   * If [ShadowRoot.supported] or [useShadowDom] is false, this distributes
   * children to the insertion points of the emulated ShadowRoot.
   * This is an implementation helper and should not need to be called from your
   * code.
   *
   * This is an implementation of [composition][1] and [rendering][2] from the
   * Shadow DOM spec. Currently the algorithm will replace children of this
   * component with the DOM as it should be rendered.
   *
   * Note that because we're always expanding to the render tree, and nodes are
   * expanded in a bottom up fashion, [reprojection][3] is handled naturally.
   *
   * [1]: http://dvcs.w3.org/hg/webcomponents/raw-file/tip/spec/shadow/index.html#composition
   * [2]: http://dvcs.w3.org/hg/webcomponents/raw-file/tip/spec/shadow/index.html#rendering-shadow-trees
   * [3]: http://dvcs.w3.org/hg/webcomponents/raw-file/tip/spec/shadow/index.html#reprojection
   */
  void composeChildren() {
    if (_realShadowRoot) return;

    if (_shadowRoots.length == 0) {
      // TODO(jmesserly): this is a limitation of our codegen approach.
      // We could keep the _shadowRoots around and clone(true) them, but then
      // bindings wouldn't be properly associated.
      throw new StateError('Distribution algorithm requires at least one shadow'
        ' root and can only be run once.');
    }

    var treeStack = _shadowRoots;

    // Let TREE be the youngest tree in the HOST's tree stack
    var tree = treeStack.removeLast();
    var youngestRoot = tree;
    // Let POOL be the list of nodes
    var pool = new List.from(nodes);

    // Note: reprojection logic is skipped here because composeChildren is
    // run on each component in bottom up fashion.

    var shadowInsertionPoints = [];
    var shadowInsertionTrees = [];

    while (true) {
      // Run the distribution algorithm, supplying POOL and TREE as input
      pool = _distributeNodes(tree, pool);

      // Let POINT be the first encountered active shadow insertion point in
      // TREE, in tree order
      var point = tree.query('shadow');
      if (point != null) {
        if (treeStack.length > 0) {
          // Find the next older tree, relative to TREE in the HOST's tree stack
          // Set TREE to be this older tree
          tree = treeStack.removeLast();
          // Assign TREE to the POINT

          // Note: we defer the actual tree replace operation until the end, so
          // we can run _distributeNodes on this tree. This simplifies the query
          // for content nodes in tree order.
          shadowInsertionPoints.add(point);
          shadowInsertionTrees.add(tree);

          // Continue to repeat
        } else {
          // If we've hit a built-in element, just use a content selector.
          // This matches the behavior of built-in HTML elements.
          // Since <content> can be implemented simply, we just inline it.
          _distribute(point, pool);

          // If there is no older tree, stop.
          break;
        }
      } else {
        // If POINT exists: ... Otherwise, stop
        break;
      }
    }

    // Handle shadow tree assignments that we deferred earlier.
    for (int i = 0; i < shadowInsertionPoints.length; i++) {
      var point = shadowInsertionPoints[i];
      var tree = shadowInsertionTrees[i];
      _distribute(point, tree.nodes);
    }

    // Replace our child nodes with the ones in the youngest root.
    nodes.clear();
    nodes.addAll(youngestRoot.nodes);
  }


  /**
   * This is an implementation of the [distribution algorithm][1] from the
   * Shadow DOM spec.
   *
   * [1]: http://dvcs.w3.org/hg/webcomponents/raw-file/tip/spec/shadow/index.html#dfn-distribution-algorithm
   */
  List<Node> _distributeNodes(Element tree, List<Node> pool) {
    // Repeat for each active insertion point in TREE, in tree order:
    for (var insertionPoint in tree.queryAll('content')) {
      if (!_isActive(insertionPoint)) continue;
      // Let POINT be the current insertion point.

      // TODO(jmesserly): validate selector, as specified here:
      // http://dvcs.w3.org/hg/webcomponents/raw-file/tip/spec/shadow/index.html#matching-insertion-points
      var select = insertionPoint.attributes['select'];
      if (select == null || select == '') select = '*';

      // Repeat for each node in POOL:
      //     1. Let NODE be the current node
      //     2. If the NODE matches POINT's matching criteria:
      //         1. Distribute the NODE to POINT
      //         2. Remove NODE from the POOL

      var matching = [];
      var notMatching = [];
      for (var node in pool) {
        (_matches(node, select) ? matching : notMatching).add(node);
      }

      if (matching.length == 0) {
        // When an insertion point or a shadow insertion point has nothing
        // assigned or distributed to them, the fallback content must be used
        // instead when rendering. The fallback content is all descendants of
        // the element that represents the insertion point.
        matching = insertionPoint.nodes;
      }

      _distribute(insertionPoint, matching);

      pool = notMatching;
    }

    return pool;
  }

  static bool _matches(Node node, String selector) {
    if (node is! Element) return selector == '*';
    return (node as Element).matches(selector);
  }

  static bool _isInsertionPoint(Element node) =>
      node.tagName == 'CONTENT' || node.tagName == 'SHADOW';

  /**
   * An insertion point is "active" if it is not the child of another insertion
   * point. A child of an insertion point is "fallback" content and should not
   * be considered during the distribution algorithm.
   */
  static bool _isActive(Element node) {
    assert(_isInsertionPoint(node));
    for (node = node.parent; node != null; node = node.parent) {
      if (_isInsertionPoint(node)) return false;
    }
    return true;
  }

  /** Distribute the [nodes] in place of an existing [insertionPoint]. */
  static void _distribute(Element insertionPoint, Iterable<Node> nodes) {
    assert(_isInsertionPoint(insertionPoint));
    insertionPoint.parent.insertAllBefore(nodes, insertionPoint);
    insertionPoint.remove();
  }

  // TODO(jmesserly): this forwarding is temporary until Dart supports
  // subclassing Elements.
  // TODO(jmesserly): we were missing the setter for title, are other things
  // missing setters?

  List<Node> get nodes => host.nodes;

  set nodes(Iterable<Node> value) { host.nodes = value; }

  /**
   * Replaces this node with another node.
   */
  Node replaceWith(Node otherNode) { host.replaceWith(otherNode); }

  /**
   * Removes this node from the DOM.
   */
  void remove() => host.remove();

  Node get nextNode => host.nextNode;

  Document get document => host.document;

  Node get previousNode => host.previousNode;

  String get text => host.text;

  set text(String v) { host.text = v; }

  bool contains(Node other) => host.contains(other);

  bool hasChildNodes() => host.hasChildNodes();

  Node insertBefore(Node newChild, Node refChild) =>
    host.insertBefore(newChild, refChild);

  Node insertAllBefore(Iterable<Node> newChild, Node refChild) =>
    host.insertAllBefore(newChild, refChild);

  Map<String, String> get attributes => host.attributes;
  set attributes(Map<String, String> value) {
    host.attributes = value;
  }

  List<Element> get elements => host.children;

  set elements(List<Element> value) {
    host.children = value;
  }

  List<Element> get children => host.children;

  set children(List<Element> value) {
    host.children = value;
  }

  Set<String> get classes => host.classes;

  set classes(Iterable<String> value) {
    host.classes = value;
  }

  Map<String, String> getNamespacedAttributes(String namespace) =>
      host.getNamespacedAttributes(namespace);

  CssStyleDeclaration getComputedStyle([String pseudoElement])
    => host.getComputedStyle(pseudoElement);

  Element clone(bool deep) => host.clone(deep);

  Element get parent => host.parent;

  Node get parentNode => host.parentNode;

  String get nodeValue => host.nodeValue;

  @deprecated
  // TODO(sigmund): restore the old return type and call host.on when
  // dartbug.com/8131 is fixed.
  dynamic get on { throw new UnsupportedError('on is deprecated'); }

  String get contentEditable => host.contentEditable;

  String get dir => host.dir;

  bool get draggable => host.draggable;

  bool get hidden => host.hidden;

  String get id => host.id;

  String get innerHTML => host.innerHtml;

  void set innerHTML(String v) {
    host.innerHtml = v;
  }

  String get innerHtml => host.innerHtml;
  void set innerHtml(String v) {
    host.innerHtml = v;
  }

  bool get isContentEditable => host.isContentEditable;

  String get lang => host.lang;

  String get outerHtml => host.outerHtml;

  bool get spellcheck => host.spellcheck;

  int get tabIndex => host.tabIndex;

  String get title => host.title;

  set title(String value) { host.title = value; }

  bool get translate => host.translate;

  String get dropzone => host.dropzone;

  void click() { host.click(); }

  Element insertAdjacentElement(String where, Element element) =>
    host.insertAdjacentElement(where, element);

  void insertAdjacentHtml(String where, String html) {
    host.insertAdjacentHtml(where, html);
  }

  void insertAdjacentText(String where, String text) {
    host.insertAdjacentText(where, text);
  }

  Map<String, String> get dataset => host.dataset;

  set dataset(Map<String, String> value) {
    host.dataset = value;
  }

  Element get nextElementSibling => host.nextElementSibling;

  Element get offsetParent => host.offsetParent;

  Element get previousElementSibling => host.previousElementSibling;

  CssStyleDeclaration get style => host.style;

  String get tagName => host.tagName;

  String get pseudo => host.pseudo;

  void set pseudo(String value) {
    host.pseudo = value;
  }

  ShadowRoot get shadowRoot => host.shadowRoot;

  void blur() { host.blur(); }

  void focus() { host.focus(); }

  void scrollByLines(int lines) {
    host.scrollByLines(lines);
  }

  void scrollByPages(int pages) {
    host.scrollByPages(pages);
  }

  void scrollIntoView([ScrollAlignment alignment]) {
    host.scrollIntoView(alignment);
  }

  bool matches(String selectors) => host.matches(selectors);

  void requestFullScreen(int flags) {
    host.requestFullScreen(flags);
  }

  void requestFullscreen() { host.requestFullscreen(); }

  void requestPointerLock() { host.requestPointerLock(); }

  Element query(String selectors) => host.query(selectors);

  List<Element> queryAll(String selectors) => host.queryAll(selectors);

  HtmlCollection get $dom_children => host.$dom_children;

  int get $dom_childElementCount => host.$dom_childElementCount;

  String get $dom_className => host.$dom_className;
  set $dom_className(String value) { host.$dom_className = value; }

  @deprecated
  int get clientHeight => client.height;

  @deprecated
  int get clientLeft => client.left;

  @deprecated
  int get clientTop => client.top;

  @deprecated
  int get clientWidth => client.width;

  Rect get client => host.client;

  Element get $dom_firstElementChild => host.$dom_firstElementChild;

  Element get $dom_lastElementChild => host.$dom_lastElementChild;

  @deprecated
  int get offsetHeight => offset.height;

  @deprecated
  int get offsetLeft => offset.left;

  @deprecated
  int get offsetTop => offset.top;

  @deprecated
  int get offsetWidth => offset.width;

  Rect get offset => host.offset;

  int get scrollHeight => host.scrollHeight;

  int get scrollLeft => host.scrollLeft;

  int get scrollTop => host.scrollTop;

  set scrollLeft(int value) { host.scrollLeft = value; }

  set scrollTop(int value) { host.scrollTop = value; }

  int get scrollWidth => host.scrollWidth;

  String $dom_getAttribute(String name) =>
      host.$dom_getAttribute(name);

  String $dom_getAttributeNS(String namespaceUri, String localName) =>
      host.$dom_getAttributeNS(namespaceUri, localName);

  String $dom_setAttributeNS(
      String namespaceUri, String localName, String value) {
    host.$dom_setAttributeNS(namespaceUri, localName, value);
  }

  bool $dom_hasAttributeNS(String namespaceUri, String localName) =>
      host.$dom_hasAttributeNS(namespaceUri, localName);

  void $dom_removeAttributeNS(String namespaceUri, String localName) =>
      host.$dom_removeAttributeNS(namespaceUri, localName);

  Rect getBoundingClientRect() => host.getBoundingClientRect();

  List<Rect> getClientRects() => host.getClientRects();

  List<Node> getElementsByClassName(String name) =>
      host.getElementsByClassName(name);

  List<Node> $dom_getElementsByTagName(String name) =>
      host.$dom_getElementsByTagName(name);

  bool $dom_hasAttribute(String name) =>
      host.$dom_hasAttribute(name);

  List<Node> $dom_querySelectorAll(String selectors) =>
      host.$dom_querySelectorAll(selectors);

  void $dom_removeAttribute(String name) =>
      host.$dom_removeAttribute(name);

  void $dom_setAttribute(String name, String value) =>
      host.$dom_setAttribute(name, value);

  get $dom_attributes => host.$dom_attributes;

  List<Node> get $dom_childNodes => host.$dom_childNodes;

  Node get $dom_firstChild => host.$dom_firstChild;

  Node get $dom_lastChild => host.$dom_lastChild;

  String get localName => host.localName;

  String get $dom_namespaceUri => host.$dom_namespaceUri;

  int get nodeType => host.nodeType;

  void $dom_addEventListener(String type, EventListener listener,
                             [bool useCapture]) {
    host.$dom_addEventListener(type, listener, useCapture);
  }

  bool dispatchEvent(Event event) => host.dispatchEvent(event);

  Node $dom_removeChild(Node oldChild) => host.$dom_removeChild(oldChild);

  void $dom_removeEventListener(String type, EventListener listener,
                                [bool useCapture]) {
    host.$dom_removeEventListener(type, listener, useCapture);
  }

  Node $dom_replaceChild(Node newChild, Node oldChild) =>
      host.$dom_replaceChild(newChild, oldChild);

  get xtag => host.xtag;

  set xtag(value) { host.xtag = value; }

  Node append(Node e) => host.append(e);

  void appendText(String text) => host.appendText(text);

  void appendHtml(String html) => host.appendHtml(html);

  void $dom_scrollIntoView([bool alignWithTop]) {
    if (alignWithTop == null) {
      host.$dom_scrollIntoView();
    } else {
      host.$dom_scrollIntoView(alignWithTop);
    }
  }

  void $dom_scrollIntoViewIfNeeded([bool centerIfNeeded]) {
    if (centerIfNeeded == null) {
      host.$dom_scrollIntoViewIfNeeded();
    } else {
      host.$dom_scrollIntoViewIfNeeded(centerIfNeeded);
    }
  }

  String get regionOverset => host.regionOverset;

  List<Range> getRegionFlowRanges() => host.getRegionFlowRanges();

  // TODO(jmesserly): rename "created" to "onCreated".
  void onCreated() => created();

  Node get insertionParent => host.insertionParent;

  Stream<Event> get onAbort => host.onAbort;
  Stream<Event> get onBeforeCopy => host.onBeforeCopy;
  Stream<Event> get onBeforeCut => host.onBeforeCut;
  Stream<Event> get onBeforePaste => host.onBeforePaste;
  Stream<Event> get onBlur => host.onBlur;
  Stream<Event> get onChange => host.onChange;
  Stream<MouseEvent> get onClick => host.onClick;
  Stream<MouseEvent> get onContextMenu => host.onContextMenu;
  Stream<Event> get onCopy => host.onCopy;
  Stream<Event> get onCut => host.onCut;
  Stream<Event> get onDoubleClick => host.onDoubleClick;
  Stream<MouseEvent> get onDrag => host.onDrag;
  Stream<MouseEvent> get onDragEnd => host.onDragEnd;
  Stream<MouseEvent> get onDragEnter => host.onDragEnter;
  Stream<MouseEvent> get onDragLeave => host.onDragLeave;
  Stream<MouseEvent> get onDragOver => host.onDragOver;
  Stream<MouseEvent> get onDragStart => host.onDragStart;
  Stream<MouseEvent> get onDrop => host.onDrop;
  Stream<Event> get onError => host.onError;
  Stream<Event> get onFocus => host.onFocus;
  Stream<Event> get onInput => host.onInput;
  Stream<Event> get onInvalid => host.onInvalid;
  Stream<KeyboardEvent> get onKeyDown => host.onKeyDown;
  Stream<KeyboardEvent> get onKeyPress => host.onKeyPress;
  Stream<KeyboardEvent> get onKeyUp => host.onKeyUp;
  Stream<Event> get onLoad => host.onLoad;
  Stream<MouseEvent> get onMouseDown => host.onMouseDown;
  Stream<MouseEvent> get onMouseMove => host.onMouseMove;
  Stream<Event> get onFullscreenChange => host.onFullscreenChange;
  Stream<Event> get onFullscreenError => host.onFullscreenError;
  Stream<Event> get onPaste => host.onPaste;
  Stream<Event> get onReset => host.onReset;
  Stream<Event> get onScroll => host.onScroll;
  Stream<Event> get onSearch => host.onSearch;
  Stream<Event> get onSelect => host.onSelect;
  Stream<Event> get onSelectStart => host.onSelectStart;
  Stream<Event> get onSubmit => host.onSubmit;
  Stream<MouseEvent> get onMouseOut => host.onMouseOut;
  Stream<MouseEvent> get onMouseOver => host.onMouseOver;
  Stream<MouseEvent> get onMouseUp => host.onMouseUp;
  Stream<TouchEvent> get onTouchCancel => host.onTouchCancel;
  Stream<TouchEvent> get onTouchEnd => host.onTouchEnd;
  Stream<TouchEvent> get onTouchEnter => host.onTouchEnter;
  Stream<TouchEvent> get onTouchLeave => host.onTouchLeave;
  Stream<TouchEvent> get onTouchMove => host.onTouchMove;
  Stream<TouchEvent> get onTouchStart => host.onTouchStart;
  Stream<TransitionEvent> get onTransitionEnd => host.onTransitionEnd;

  // TODO(sigmund): do the normal forwarding when dartbug.com/7919 is fixed.
  Stream<WheelEvent> get onMouseWheel {
    throw new UnsupportedError('onMouseWheel is not supported');
  }
}

/**
 * Set this to true to use native Shadow DOM if it is supported.
 * Note that this will change behavior of [WebComponent] APIs for tree
 * traversal.
 */
bool useShadowDom = false;

bool get _realShadowRoot => useShadowDom && ShadowRoot.supported;
