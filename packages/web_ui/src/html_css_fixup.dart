// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library html_css_fixup;

import 'dart:json' as json;

import 'package:csslib/visitor.dart';
import 'package:html5lib/dom.dart';
import 'package:html5lib/dom_parsing.dart';

import 'info.dart';
import 'messages.dart';
import 'options.dart';
import 'paths.dart';
import 'utils.dart';

/**
 *  If processCss is enabled, prefix any component's HTML attributes for id or
 *  class to reference the mangled CSS class name or id.
 *
 *  Adds prefix error/warning messages to [messages], if [messages] is
 *  supplied.
 */
void fixupHtmlCss(FileInfo fileInfo, CompilerOptions opts) {
  // Walk the HTML tree looking for class names or id that are in our parsed
  // stylesheet selectors and making those CSS classes and ids unique to that
  // component.
  if (opts.verbose) print("  CSS fixup ${path.basename(fileInfo.inputPath)}");
  for (var component in fileInfo.declaredComponents) {
    // TODO(terry): Consider allowing more than one style sheet per component.
    // For components only 1 stylesheet allowed.
    if (component.styleSheets.length == 1) {
      var styleSheet = component.styleSheets[0];
      // If polyfill is on prefix component name to all CSS classes and ids
      // referenced in the scoped style.
      var prefix = opts.processCss ? component.tagName : null;
      // List of referenced #id and .class in CSS.
      var knownCss = new IdClassVisitor()..visitTree(styleSheet);
      // Prefix all id and class refs in CSS selectors and HTML attributes.
      new _ScopedStyleRenamer(knownCss, prefix, opts.debugCss).visit(component);
    }
  }
}

/** Build list of every CSS class name and id selector in a stylesheet. */
class IdClassVisitor extends Visitor {
  final Set<String> classes = new Set();
  final Set<String> ids = new Set();

  void visitClassSelector(ClassSelector node) {
    classes.add(node.name);
  }

  void visitIdSelector(IdSelector node) {
    ids.add(node.name);
  }
}

/** Build the Dart `_css` list of managled class names. */
Map createCssSimpleSelectors(IdClassVisitor visitedCss, ComponentInfo info,
                     {scopedStyles: true}) {
  Map selectors = {};
  if (visitedCss != null) {
    for (var cssClass in visitedCss.classes) {
      selectors['.$cssClass'] =
          scopedStyles ? '${info.tagName}_$cssClass' : cssClass;
    }
    for (var id in visitedCss.ids) {
      selectors['#$id'] = scopedStyles ? '${info.tagName}_$id' : id;
    }
  }
  return selectors;
}

/**
 * Return a map of simple CSS selectors (class and id selectors) as a Dart map
 * definition.
 */
String createCssSelectorsDefinition(ComponentInfo info, bool cssPolyfill) {
  var cssVisited = new IdClassVisitor();

  // For components only 1 stylesheet allowed.
  if (!info.styleSheets.isEmpty && info.styleSheets.length == 1) {
    var styleSheet = info.styleSheets[0];
    cssVisited..visitTree(styleSheet);
  }

  var css = json.stringify(createCssSimpleSelectors(cssVisited, info,
      scopedStyles: cssPolyfill));
  return 'static Map<String, String> _css = $css;';
}

// TODO(terry): Do we need to handle other selectors than IDs/classes?
// TODO(terry): Would be nice if we didn't need to mangle names; requires users
//              to be careful in their code and makes it more than a "polyfill".
//              Maybe mechanism that generates CSS class name for scoping.
/**
 * Fix a component's HTML to implement scoped stylesheets.
 *
 * We do this by renaming all element class and id attributes to be globally
 * unique to a component.
 *
 * This phase runs after the analyzer and html_cleaner; at that point it's a
 * tree of Infos.  We need to walk element Infos but mangle the HTML elements.
 */
class _ScopedStyleRenamer extends InfoVisitor {
  final bool _debugCss;

  /** Set of classes and ids defined for this component. */
  final IdClassVisitor _knownCss;

  /** Prefix to apply to each class/id reference. */
  final String _prefix;

  _ScopedStyleRenamer(this._knownCss, this._prefix, this._debugCss);

  void visitElementInfo(ElementInfo info) {
    // Walk the HTML elements mangling any references to id or class attributes.
    _mangleClassAttribute(info.node, _knownCss.classes, _prefix);
    _mangleIdAttribute(info.node, _knownCss.ids, _prefix);

    super.visitElementInfo(info);
  }

  /**
   * Mangles HTML class reference that matches a CSS class name defined in the
   * component's style sheet.
   */
  void _mangleClassAttribute(Node node, Set<String> classes, String prefix) {
    if (node.attributes.containsKey('class')) {
      var refClasses = node.attributes['class'].trim().split(" ");

      bool changed = false;
      var len = refClasses.length;
      for (var i = 0; i < len; i++) {
        var refClass = refClasses[i];
        if (classes.contains(refClass)) {
          if (prefix != null) {
            refClasses[i] = "${prefix}_$refClass";
            changed = true;
          }
        }
      }

      if (changed) {
        StringBuffer newClasses = new StringBuffer();
        refClasses.forEach((String className) {
          newClasses.write("${(newClasses.length > 0) ? ' ' : ''}$className");
        });
        var mangledClasses = newClasses.toString();
        if (_debugCss) {
          print("    class = ${node.attributes['class'].trim()} => "
          "$mangledClasses");
        }
        node.attributes['class'] = mangledClasses;
      }
    }
  }

  /**
   * Mangles an HTML id reference that matches a CSS id selector name defined
   * in the component's style sheet.
   */
  void _mangleIdAttribute(Node node, Set<String> ids, String prefix) {
    if (prefix != null) {
      var id = node.attributes['id'];
      if (id != null && ids.contains(id)) {
        var mangledName = "${prefix}_$id";
        if (_debugCss) {
          print("    id = ${node.attributes['id'].toString()} => $mangledName");
        }
        node.attributes['id'] = mangledName;
      }
    }
  }
}

/** Compute each CSS URI resource relative from the generated CSS file. */
class UriVisitor extends Visitor {
  /**
   * Relative path from the output css file to the location of the original
   * css file that contained the URI to each resource.
   */
  final String _pathToOriginalCss;

  factory UriVisitor(PathMapper pathMapper, String cssPath, bool rewriteUrl) {
    var cssDir = path.dirname(cssPath);
    var outCssDir = rewriteUrl ? pathMapper.outputDirPath(cssPath)
        : path.dirname(cssPath);
    return new UriVisitor._internal(path.relative(cssDir, from: outCssDir));
  }

  UriVisitor._internal(this._pathToOriginalCss);

  void visitUriTerm(UriTerm node) {
    node.text = PathMapper.toUrl(
        path.normalize(path.join(_pathToOriginalCss, node.text)));
  }
}

/**
 * Find any imports in the style sheet; normalize the style sheet href and
 * return a list of all fully qualified CSS files.
 */
class CssImports extends Visitor {
  final String packageRoot;
  final FileInfo fileInfo;

  /** List of all imported style sheets. */
  final List<UrlInfo> urlInfos = [];

  CssImports(this.packageRoot, this.fileInfo);

  void visitTree(StyleSheet tree) {
    visitStyleSheet(tree);
  }

  void visitImportDirective(ImportDirective node) {
    var urlInfo = UrlInfo.resolve(packageRoot, fileInfo.inputPath, node.import,
        node.span, isCss: true);
    if (urlInfo == null) return;
    urlInfos.add(urlInfo);
  }
}
