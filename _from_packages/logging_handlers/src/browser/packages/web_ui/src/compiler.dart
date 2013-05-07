// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library compiler;

import 'dart:async';
import 'dart:collection' show SplayTreeMap;
import 'dart:json' as json;
import 'package:analyzer_experimental/src/generated/ast.dart' show Directive, UriBasedDirective;
import 'package:csslib/parser.dart' as css;
import 'package:csslib/visitor.dart' show StyleSheet, treeToDebugString, Visitor;
import 'package:html5lib/dom.dart';
import 'package:html5lib/parser.dart';
import 'package:source_maps/span.dart' show Span;

import 'analyzer.dart';
import 'code_printer.dart';
import 'codegen.dart' as codegen;
import 'dart_parser.dart';
import 'emitters.dart';
import 'file_system.dart';
import 'files.dart';
import 'html_cleaner.dart';
import 'html_css_fixup.dart';
import 'info.dart';
import 'messages.dart';
import 'observable_transform.dart' show transformObservables;
import 'options.dart';
import 'paths.dart';
import 'refactor.dart';
import 'utils.dart';

/**
 * Parses an HTML file [contents] and returns a DOM-like tree.
 * Note that [contents] will be a [String] if coming from a browser-based
 * [FileSystem], or it will be a [List<int>] if running on the command line.
 *
 * Adds emitted error/warning to [messages], if [messages] is supplied.
 */
Document parseHtml(contents, String sourcePath, Messages messages) {
  var parser = new HtmlParser(contents, generateSpans: true,
      sourceUrl: sourcePath);
  var document = parser.parse();

  // Note: errors aren't fatal in HTML (unless strict mode is on).
  // So just print them as warnings.
  for (var e in parser.errors) {
    messages.warning(e.message, e.span);
  }
  return document;
}

/** Compiles an application written with Dart web components. */
class Compiler {
  final FileSystem fileSystem;
  final CompilerOptions options;
  final List<SourceFile> files = <SourceFile>[];
  final List<OutputFile> output = <OutputFile>[];

  String _mainPath;
  PathMapper _pathMapper;
  Messages _messages;

  FutureGroup _tasks;
  Set _processed;

  bool _useObservers = false;

  /** Information about source [files] given their href. */
  final Map<String, FileInfo> info = new SplayTreeMap<String, FileInfo>();
  final _edits = new Map<DartCodeInfo, TextEditTransaction>();

 /**
  * Creates a compiler with [options] using [fileSystem].
  *
  * Adds emitted error/warning messages to [messages], if [messages] is
  * supplied.
  */
  Compiler(this.fileSystem, this.options, this._messages) {
    _mainPath = options.inputFile;
    var mainDir = path.dirname(_mainPath);
    var baseDir = options.baseDir != null ? options.baseDir : mainDir;
    var outputDir = options.outputDir != null ? options.outputDir : mainDir;
    var packageRoot = options.packageRoot != null ? options.packageRoot
        : path.join(path.dirname(_mainPath), 'packages');

    // Normalize paths - all should be relative or absolute paths.
    if (path.isAbsolute(_mainPath) || path.isAbsolute(baseDir) ||
        path.isAbsolute(outputDir) || path.isAbsolute(packageRoot)) {
      if (path.isRelative(_mainPath)) _mainPath = path.resolve(_mainPath);
      if (path.isRelative(baseDir)) baseDir = path.resolve(baseDir);
      if (path.isRelative(outputDir)) outputDir = path.resolve(outputDir);
      if (path.isRelative(packageRoot)) {
        packageRoot = path.resolve(packageRoot);
      }
    }
    _pathMapper = new PathMapper(
        baseDir, outputDir, packageRoot, options.forceMangle);
  }

  /** Compile the application starting from the given [mainFile]. */
  Future run() {
    if (path.basename(_mainPath).endsWith('.dart')) {
      _messages.error("Please provide an HTML file as your entry point.",
          null);
      return new Future.value(null);
    }
    return _parseAndDiscover(_mainPath).then((_) {
      _analyze();
      // TODO(jmesserly): need to go through our errors, and figure out if some
      // of them should be warnings instead.
      if (_messages.hasErrors) return;
      _transformDart();
      _emit();
    });
  }

  /**
   * Asynchronously parse [inputFile] and transitively discover web components
   * to load and parse. Returns a future that completes when all files are
   * processed.
   */
  Future _parseAndDiscover(String inputFile) {
    _tasks = new FutureGroup();
    _processed = new Set();
    _processed.add(inputFile);
    _tasks.add(_parseHtmlFile(new UrlInfo(inputFile, null)));
    return _tasks.future;
  }

  void _processHtmlFile(SourceFile file) {
    if (file == null) return;

    bool isEntryPoint = _processed.length == 1;

    files.add(file);

    var fileInfo = _time('Analyzed definitions', file.path,
        () => analyzeDefinitions(file, _pathMapper.packageRoot, _messages,
            isEntryPoint: isEntryPoint));
    info[file.path] = fileInfo;

    _setOutputFilenames(fileInfo);
    _processImports(fileInfo);

    // Load component files referenced by [file].
    for (var link in fileInfo.componentLinks) {
      _loadFile(link, _parseHtmlFile);
    }

    // Load stylesheet files referenced by [file].
    for (var link in fileInfo.styleSheetHref) {
      _loadFile(link, _parseCssFile);
    }

    // Load .dart files being referenced in the page.
    _loadFile(fileInfo.externalFile, _parseDartFile);

    // Load .dart files being referenced in components.
    for (var component in fileInfo.declaredComponents) {
      if (component.externalFile != null) {
        _loadFile(component.externalFile, _parseDartFile);
      } else if (component.userCode != null) {
        _processImports(component);
      }
    }
  }

  /**
   * Helper function to load [urlInfo] and parse it using [loadAndParse] if it
   * hasn't been loaded before.
   */
  void _loadFile(UrlInfo urlInfo, Future loadAndParse(UrlInfo inputUrl)) {
    if (urlInfo == null) return;
    var resolvedPath = urlInfo.resolvedPath;
    if (!_processed.contains(resolvedPath)) {
      _processed.add(resolvedPath);
      _tasks.add(loadAndParse(urlInfo));
    }
  }

  void _setOutputFilenames(FileInfo fileInfo) {
    var filePath = fileInfo.dartCodePath;
    fileInfo.outputFilename = _pathMapper.mangle(path.basename(filePath),
        '.dart', path.extension(filePath) == '.html');
    for (var component in fileInfo.declaredComponents) {
      var externalFile = component.externalFile;
      var name = null;
      if (externalFile != null) {
        name = _pathMapper.mangle(
            path.basename(externalFile.resolvedPath), '.dart');
      } else {
        var declaringFile = component.declaringFile;
        var prefix = path.basename(declaringFile.inputPath);
        if (declaringFile.declaredComponents.length == 1
            && !declaringFile.codeAttached && !declaringFile.isEntryPoint) {
          name = _pathMapper.mangle(prefix, '.dart', true);
        } else {
          var componentName = component.tagName.replaceAll('-', '_');
          name = _pathMapper.mangle('${prefix}_$componentName', '.dart', true);
        }
      }
      component.outputFilename = name;
    }
  }

  /** Parse an HTML file. */
  Future _parseHtmlFile(UrlInfo inputPath) {
    if (!_pathMapper.checkInputPath(inputPath, _messages)) {
      return new Future<SourceFile>.value(null);
    }
    var filePath = inputPath.resolvedPath;
    return fileSystem.readTextOrBytes(filePath)
        .catchError((e) => _readError(e, inputPath))
        .then((source) {
          if (source == null) return;
          var file = new SourceFile(filePath);
          file.document = _time('Parsed', filePath,
              () => parseHtml(source, filePath, _messages));
          _processHtmlFile(file);
        });
  }

  /** Parse a Dart file. */
  Future _parseDartFile(UrlInfo inputPath) {
    if (!_pathMapper.checkInputPath(inputPath, _messages)) {
      return new Future<SourceFile>.value(null);
    }
    var filePath = inputPath.resolvedPath;
    return fileSystem.readText(filePath)
        .catchError((e) => _readError(e, inputPath))
        .then((code) {
          if (code == null) return;
          var file = new SourceFile(filePath, type: SourceFile.DART);
          file.code = code;
          _processDartFile(file);
        });
  }

  /** Parse a stylesheet file. */
  Future _parseCssFile(UrlInfo inputPath) {
    if (!options.processCss ||
        !_pathMapper.checkInputPath(inputPath, _messages)) {
      return new Future<SourceFile>.value(null);
    }
    var filePath = inputPath.resolvedPath;
    return fileSystem.readText(filePath)
        .catchError((e) => _readError(e, inputPath, isWarning: true))
        .then((code) {
          if (code == null) return;
          var file = new SourceFile(filePath, type: SourceFile.STYLESHEET);
          file.code = code;
          _processCssFile(file);
        });
  }


  SourceFile _readError(error, UrlInfo inputPath, {isWarning: false}) {
    var message = 'unable to open file "${inputPath.resolvedPath}"';
    if (options.verbose) {
      message = '$message. original message:\n $error';
    }
    if (isWarning) {
      _messages.warning(message, inputPath.sourceSpan);
    } else {
      _messages.error(message, inputPath.sourceSpan);
    }
    return null;
  }

  void _processDartFile(SourceFile dartFile) {
    if (dartFile == null) return;

    files.add(dartFile);

    var fileInfo = new FileInfo(dartFile.path);
    info[dartFile.path] = fileInfo;
    fileInfo.inlinedCode =
        parseDartCode(fileInfo.inputPath, dartFile.code, _messages);
    fileInfo.outputFilename =
        _pathMapper.mangle(path.basename(dartFile.path), '.dart', false);

    _processImports(fileInfo);
  }

  void _processImports(LibraryInfo library) {
    if (library.userCode == null) return;

    for (var directive in library.userCode.directives) {
      var src = _getDirectivePath(library, directive);
      if (src == null) {
        var uri = directive.uri.value;
        if (uri.startsWith('package:web_ui/observe')) {
          _useObservers = true;
        }
      } else {
        var urlInfo = new UrlInfo(src,
            library.userCode.sourceFile.span(directive.offset, directive.end));
        _loadFile(urlInfo, _parseDartFile);
      }
    }
  }

  void _processCssFile(SourceFile cssFile) {
    if (cssFile == null) return;

    files.add(cssFile);

    var fileInfo = new FileInfo(cssFile.path);
    info[cssFile.path] = fileInfo;

    var styleSheet = _parseCss(cssFile.code, cssFile.path, _messages, options);
    if (styleSheet != null) {
      var urlInfos = _time('CSS imports', cssFile.path, () =>
          (new CssImports(_pathMapper.packageRoot, fileInfo)
              ..visitTree(styleSheet)).urlInfos);

      fileInfo.styleSheets.add(styleSheet);

      for (var urlInfo in urlInfos) {
        if (urlInfo == null) break;

        fileInfo.styleSheetHref.add(urlInfo);

        // Load any @imported stylesheet files referenced in this style sheet.
        _loadFile(urlInfo, _parseCssFile);
      }
    }
  }

  String _getDirectivePath(LibraryInfo libInfo, Directive directive) {
    var uriDirective = (directive as UriBasedDirective).uri;
    var uri = uriDirective.value;
    if (uri.startsWith('dart:')) return null;

    if (uri.startsWith('package:')) {
      // Don't process our own package -- we'll implement @observable manually.
      if (uri.startsWith('package:web_ui/')) return null;

      return path.join(_pathMapper.packageRoot, uri.substring(8));
    } else {
      return path.normalize(
          path.join(path.dirname(libInfo.dartCodePath), uri));
    }
  }

  /**
   * Transform Dart source code.
   * Currently, the only transformation is [transformObservables].
   * Calls _emitModifiedDartFiles to write the transformed files.
   */
  void _transformDart() {
    var libraries = _findAllDartLibraries();

    var transformed = [];
    for (var lib in libraries) {
      var transaction = transformObservables(lib.userCode);
      if (transaction != null) {
        _edits[lib.userCode] = transaction;
        if (transaction.hasEdits) {
          _useObservers = true;
          transformed.add(lib);
        } else if (lib.htmlFile != null) {
          // All web components will be transformed too. Track that.
          transformed.add(lib);
        }
      }
    }

    _findModifiedDartFiles(libraries, transformed);

    libraries.forEach(_fixImports);

    _emitModifiedDartFiles(libraries);
  }

  /**
   * Finds all Dart code libraries.
   * Each library will have [LibraryInfo.inlinedCode] that is non-null.
   * Also each inlinedCode will be unique.
   */
  List<LibraryInfo> _findAllDartLibraries() {
    var libs = <LibraryInfo>[];
    void _addLibrary(LibraryInfo lib) {
      if (lib.inlinedCode != null) libs.add(lib);
    }

    for (var sourceFile in files) {
      var file = info[sourceFile.path];
      _addLibrary(file);
      file.declaredComponents.forEach(_addLibrary);
    }

    // Assert that each file path is unique.
    assert(_uniquePaths(libs));
    return libs;
  }

  bool _uniquePaths(List<LibraryInfo> libs) {
    var seen = new Set();
    for (var lib in libs) {
      if (seen.contains(lib.inlinedCode)) {
        throw new StateError('internal error: '
            'duplicate user code for ${lib.dartCodePath}. Files were: $files');
      }
      seen.add(lib.inlinedCode);
    }
    return true;
  }

  /**
   * Queue modified Dart files to be written.
   * This will not write files that are handled by [WebComponentEmitter] and
   * [MainPageEmitter].
   */
  void _emitModifiedDartFiles(List<LibraryInfo> libraries) {
    for (var lib in libraries) {
      // Components will get emitted by WebComponentEmitter, and the
      // entry point will get emitted by MainPageEmitter.
      // So we only need to worry about other .dart files.
      if (lib.modified && lib is FileInfo &&
          lib.htmlFile == null && !lib.isEntryPoint) {
        var transaction = _edits[lib.userCode];

        // Save imports that were modified by _fixImports.
        for (var d in lib.userCode.directives) {
          transaction.edit(d.offset, d.end, d.toString());
        }

        if (!lib.userCode.isPart) {
          var pos = lib.userCode.firstPartOffset;
          // Note: we use a different prefix than "autogenerated" to make
          // ChangeRecord unambiguous. Otherwise it would be imported by this
          // and web_ui, resulting in a collision.
          // TODO(jmesserly): only generate this for libraries that need it.
          transaction.edit(pos, pos, "\nimport "
              "'package:web_ui/observe/observable.dart' as __observe;\n");
        }
        _emitFileAndSourceMaps(lib, transaction.commit(), lib.dartCodePath);
      }
    }
  }

  /**
   * This method computes which Dart files have been modified, starting
   * from [transformed] and marking recursively through all files that import
   * the modified files.
   */
  void _findModifiedDartFiles(List<LibraryInfo> libraries,
      List<FileInfo> transformed) {

    if (transformed.length == 0) return;

    // Compute files that reference each file, then use this information to
    // flip the modified bit transitively. This is a lot simpler than trying
    // to compute it the other way because of circular references.
    for (var lib in libraries) {
      for (var directive in lib.userCode.directives) {
        var importPath = _getDirectivePath(lib, directive);
        if (importPath == null) continue;

        var importInfo = info[importPath];
        if (importInfo != null) {
          importInfo.referencedBy.add(lib);
        }
      }
    }

    // Propegate the modified bit to anything that references a modified file.
    void setModified(LibraryInfo library) {
      if (library.modified) return;
      library.modified = true;
      library.referencedBy.forEach(setModified);
    }
    transformed.forEach(setModified);

    for (var lib in libraries) {
      // We don't need this anymore, so free it.
      lib.referencedBy = null;
    }
  }

  void _fixImports(LibraryInfo library) {
    var fileOutputPath = _pathMapper.outputLibraryPath(library);

    // Fix imports. Modified files must use the generated path, otherwise
    // we need to make the path relative to the input.
    for (var directive in library.userCode.directives) {
      var importPath = _getDirectivePath(library, directive);
      if (importPath == null) continue;
      var importInfo = info[importPath];
      if (importInfo == null) continue;

      String newUri = null;
      if (importInfo.modified) {
        // Use the generated URI for this file.
        newUri = _pathMapper.relativeUrl(library, importInfo);
      } else if (options.rewriteUrls) {
        // Get the relative path to the input file.
        newUri = _pathMapper.transformUrl(library.dartCodePath,
            directive.uri.value);
      }
      if (newUri != null) {
        directive.uri = createStringLiteral(newUri);
      }
    }
  }

  /** Run the analyzer on every input html file. */
  void _analyze() {
    var uniqueIds = new IntIterator();
    for (var file in files) {
      if (file.isHtml) {
        _time('Analyzed contents', file.path, () =>
            analyzeFile(file, info, uniqueIds, _messages));
      }
    }
  }

  /** Emit the generated code corresponding to each input file. */
  void _emit() {
    for (var file in files) {
      if (file.isDart || file.isStyleSheet) continue;
      _time('Codegen', file.path, () {
        var fileInfo = info[file.path];
        cleanHtmlNodes(fileInfo);
        if (!fileInfo.isEntryPoint) {
          _processStylesheet(fileInfo, messages: _messages, options: options);
        }
        fixupHtmlCss(fileInfo, options);
        _emitComponents(fileInfo);
      });
    }

    var entryPoint = files[0];
    assert(info[entryPoint.path].isEntryPoint);
    _emitMainDart(entryPoint);
    _emitMainHtml(entryPoint);

    assert(_unqiueOutputs());
  }

  bool _unqiueOutputs() {
    var seen = new Set();
    for (var file in output) {
      if (seen.contains(file.path)) {
        throw new StateError('internal error: '
            'duplicate output file ${file.path}. Files were: $output');
      }
      seen.add(file.path);
    }
    return true;
  }

  /** Emit the main .dart file. */
  void _emitMainDart(SourceFile file) {
    var fileInfo = info[file.path];
    var printer = new EntryPointEmitter(fileInfo)
        .run(_pathMapper, _edits[fileInfo.userCode], options.rewriteUrls);
    _emitFileAndSourceMaps(fileInfo, printer, fileInfo.dartCodePath);
  }

  // TODO(jmesserly): refactor this out of Compiler.
  /** Generate an html file with the (trimmed down) main html page. */
  void _emitMainHtml(SourceFile file) {
    var fileInfo = info[file.path];

    var bootstrapName = '${path.basename(file.path)}_bootstrap.dart';
    var bootstrapPath = path.join(path.dirname(file.path), bootstrapName);
    var bootstrapOutPath = _pathMapper.outputPath(bootstrapPath, '');
    var bootstrapOutName = path.basename(bootstrapOutPath);
    output.add(new OutputFile(bootstrapOutPath, codegen.bootstrapCode(
          _pathMapper.relativeUrl(new FileInfo(bootstrapPath), fileInfo),
          _useObservers)));

    var document = file.document;
    var hasCss = _emitAllCss();
    transformMainHtml(document, fileInfo, _pathMapper, hasCss,
        options.rewriteUrls, _messages);

    document.body.nodes.add(parseFragment(
        '<script type="application/dart" src="$bootstrapOutName"></script>'));

    output.add(new OutputFile(_pathMapper.outputPath(file.path, '.html'),
        document.outerHtml, source: file.path));
  }

  // TODO(jmesserly): refactor this and other CSS related transforms out of
  // Compiler.
  /**
   * Generate an CSS file for all style sheets (main and components).
   * Returns true if a file was generated, otherwise false.
   */
  bool _emitAllCss() {
    if (!options.processCss) return false;

    var buff = new StringBuffer();

    // Emit all linked style sheet files first.
    for (var file in files) {
      var css = new StringBuffer();
      var fileInfo = info[file.path];
      if (file.isStyleSheet) {
        for (var styleSheet in fileInfo.styleSheets) {
          // Translate any URIs in CSS.
          var uriVisitor = new UriVisitor(_pathMapper, fileInfo.inputPath,
              options.rewriteUrls);
          uriVisitor.visitTree(styleSheet);

          if (options.debugCss) {
            print('\nCSS source: ${fileInfo.inputPath}');
            print('==========\n');
            print(treeToDebugString(styleSheet));
          }

          css.write(
              '/* Auto-generated from style sheet href = ${file.path} */\n'
              '/* DO NOT EDIT. */\n\n');
          css.write(emitStyleSheet(styleSheet));
          css.write('\n\n');
        }

        // Emit the linked style sheet in the output directory.
        var outCss = _pathMapper.outputPath(fileInfo.inputPath, '');
        output.add(new OutputFile(outCss, css.toString()));
      }
    }

    // Emit all CSS for each component (style scoped).
    for (var file in files) {
      if (file.isHtml) {
        var fileInfo = info[file.path];
        for (var component in fileInfo.declaredComponents) {
          for (var styleSheet in component.styleSheets) {

            // Translate any URIs in CSS.
            var uriVisitor = new UriVisitor(_pathMapper, fileInfo.inputPath,
                options.rewriteUrls);
            uriVisitor.visitTree(styleSheet);

            if (buff.isEmpty) {
              buff.write(
                  '/* Auto-generated from components style tags. */\n'
                  '/* DO NOT EDIT. */\n\n');
            }
            buff.write(
                '/* ==================================================== \n'
                '   Component ${component.tagName} stylesheet \n'
                '   ==================================================== */\n');
            buff.write(emitStyleSheet(styleSheet, component.tagName));
            buff.write('\n\n');
          }
        }
      }
    }

    if (buff.isEmpty) return false;

    var cssPath = _pathMapper.outputPath(_mainPath, '.css', true);
    output.add(new OutputFile(cssPath, buff.toString()));
    return true;
  }

  /** Emits the Dart code for all components in [fileInfo]. */
  void _emitComponents(FileInfo fileInfo) {
    for (var component in fileInfo.declaredComponents) {
      // TODO(terry): Handle one stylesheet per component see fixupHtmlCss.
      if (component.styleSheets.length > 1 && options.processCss) {
        var span = component.externalFile != null
            ? component.externalFile.sourceSpan : null;
        _messages.warning(
            'Component has more than one stylesheet - first stylesheet used.',
            span);
      }
      var printer = new WebComponentEmitter(fileInfo, _messages)
          .run(component, _pathMapper, _edits[component.userCode]);
      var codePath = component.externalFile != null
          ? component.externalFile.resolvedPath : null;
      _emitFileAndSourceMaps(component, printer, codePath);
    }
  }

  /**
   * Emits a file that was created using [CodePrinter] and it's corresponding
   * source map file.
   */
  void _emitFileAndSourceMaps(
      LibraryInfo lib, CodePrinter printer, String dartCodePath) {
    // Bail if we had an error generating the code for the file.
    if (printer == null) return;

    var libPath = _pathMapper.outputLibraryPath(lib);
    var dir = path.dirname(libPath);
    var filename = path.basename(libPath);
    printer.add('\n//@ sourceMappingURL=$filename.map');
    printer.build(libPath);
    output.add(new OutputFile(libPath, printer.text, source: dartCodePath));
    // Fix-up the paths in the source map file
    var sourceMap = json.parse(printer.map);
    var urls = sourceMap['sources'];
    for (int i = 0; i < urls.length; i++) {
      urls[i] = path.relative(urls[i], from: dir);
    }
    output.add(new OutputFile(path.join(dir, '$filename.map'),
          json.stringify(sourceMap)));
  }

  _time(String logMessage, String filePath, callback(),
      {bool printTime: false}) {
    var message = new StringBuffer();
    message.write(logMessage);
    var filename = path.basename(filePath);
    for (int i = (60 - logMessage.length - filename.length); i > 0 ; i--) {
      message.write(' ');
    }
    message.write(filename);
    return time(message.toString(), callback,
        printTime: options.verbose || printTime);
  }
}

/** Parse all stylesheet for polyfilling assciated with [info]. */
void _processStylesheet(info, {Messages messages : null,
                               CompilerOptions options : null}) {
  new _ProcessCss(messages, options).visit(info);
}

// TODO(terry): Add --checked when fully implemented and error handling.
StyleSheet _parseCss(String content, String sourcePath, Messages messages,
                     CompilerOptions opts) {
  if (!content.trim().isEmpty) {
    var errs = [];

    // TODO(terry): Add --checked when fully implemented and error handling.
    var stylesheet = css.parse(content, errors: errs, options:
        [opts.warningsAsErrors ? '--warnings_as_errors' : '', 'memory']);

    // Note: errors aren't fatal in HTML (unless strict mode is on).
    // So just print them as warnings.
    for (var e in errs) {
      messages.warning(e.message, e.span);
    }

    return stylesheet;
  }
}

/** Post-analysis of style sheet; parsed ready for emitting with polyfill. */
class _ProcessCss extends InfoVisitor {
  final Messages messages;
  final CompilerOptions options;
  ComponentInfo component;

  _ProcessCss(this.messages, this.options);

  void visitComponentInfo(ComponentInfo info) {
    var oldComponent = component;
    component = info;

    super.visitComponentInfo(info);

    component = oldComponent;
  }

  void visitElementInfo(ElementInfo info) {
    if (component != null) {
      var node = info.node;
      if (node.tagName == 'style' && node.attributes.containsKey("scoped")) {
        // Parse the contents of the scoped style tag.
        var styleSheet = _parseCss(node.nodes.single.value,
            component.declaringFile.inputPath, messages, options);
        if (styleSheet != null) {
          component.styleSheets.add(styleSheet);
        }
      }
    }

    super.visitElementInfo(info);
  }
}
