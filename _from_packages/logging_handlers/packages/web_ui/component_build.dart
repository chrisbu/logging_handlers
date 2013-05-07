// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/**
 * Common logic to make it easy to create a `build.dart` for your project.
 *
 * The `build.dart` script is invoked automatically by the Editor whenever a
 * file in the project changes. It must be placed in the root of a project
 * (where pubspec.yaml lives) and should be named exactly 'build.dart'.
 *
 * A common `build.dart` would look as follows:
 *
 *     import 'dart:io';
 *     import 'package:web_ui/component_build.dart';
 *
 *     main() => build(new Options().arguments, ['web/index.html']);
 */
library build_utils;

import 'dart:async';
import 'dart:io';
import 'dart:json' as json;
import 'package:args/args.dart';

import 'dwc.dart' as dwc;
import 'src/utils.dart';

/**
 * Set up 'build.dart' to compile with the dart web components compiler every
 * [entryPoints] listed. On clean commands, the directory where [entryPoints]
 * live will be scanned for generated files to delete them.
 */
// TODO(jmesserly): we need a better way to automatically detect input files
Future<List<dwc.CompilerResult>> build(List<String> arguments,
    List<String> entryPoints) {
  bool useColors = stdioType(stdout) == StdioType.TERMINAL;
  return asyncTime('Total time', () {
    var args = _processArgs(arguments);
    var tasks = new FutureGroup();
    var lastTask = new Future.value(null);
    tasks.add(lastTask);

    var trackDirs = <Directory>[];
    var changedFiles = args["changed"];
    var removedFiles = args["removed"];
    var cleanBuild = args["clean"];
    var machineFormat = args["machine"];
    // Also trigger a full build if the script was run from the command line
    // with no arguments
    var fullBuild = args["full"] || (!machineFormat && changedFiles.isEmpty &&
        removedFiles.isEmpty && !cleanBuild);

    for (var file in entryPoints) {
      trackDirs.add(new Directory(_outDir(file)));
    }

    if (cleanBuild) {
      _handleCleanCommand(trackDirs);
    } else if (fullBuild || changedFiles.any((f) => _isInputFile(f, trackDirs))
        || removedFiles.any((f) => _isInputFile(f, trackDirs))) {
      for (var file in entryPoints) {
        var outDir = _outDir(file);
        var dwcArgs = [];
        // Any arguments passed to build.dart after the '--'
        dwcArgs.addAll(args.rest);
        if (machineFormat) dwcArgs.add('--json_format');
        if (!useColors) dwcArgs.add('--no-colors');
        dwcArgs.addAll(['-o', outDir.toString(), file]);
        // Chain tasks to that we run one at a time.
        lastTask = lastTask.then((_) => dwc.run(dwcArgs, printTime: true));
        tasks.add(lastTask);

        if (machineFormat) {
          // Print for the Dart Editor the mapping from the input entry point
          // file and its corresponding output.
          var out = path.join(outDir, path.basename(file));
          print(json.stringify([{
            "method": "mapping",
            "params": {"from": file, "to": out},
          }]));
        }
      }
    }
    return tasks.future.then((r) => r.where((v) => v != null));
  }, printTime: true, useColors: useColors);
}

String _outDir(String file) => path.join(path.dirname(file), 'out');

bool _isGeneratedFile(String filePath, List<Directory> outputDirs) {
  var dirPrefix = path.dirname(filePath);
  for (var dir in outputDirs) {
    if (dirPrefix.startsWith(dir.path)) return true;
  }
  return path.basename(filePath).startsWith('_');
}

bool _isInputFile(String filePath, List<Directory> outputDirs) {
  var ext = path.extension(filePath);
  return (ext == '.dart' || ext == '.html') &&
      !_isGeneratedFile(filePath, outputDirs);
}

/** Delete all generated files. */
void _handleCleanCommand(List<Directory> trackDirs) {
  for (var dir in trackDirs) {
    if (!dir.existsSync()) continue;
    for (var f in dir.listSync(recursive: false)) {
      if (f is File && _isGeneratedFile(f.path, trackDirs)) f.deleteSync();
    }
  }
}

/** Process the command-line arguments. */
ArgResults _processArgs(List<String> arguments) {
  var parser = new ArgParser()
    ..addOption("changed", help: "the file has changed since the last build",
        allowMultiple: true)
    ..addOption("removed", help: "the file was removed since the last build",
        allowMultiple: true)
    ..addFlag("clean", negatable: false, help: "remove any build artifacts")
    ..addFlag("full", negatable: false, help: "perform a full build")
    ..addFlag("machine", negatable: false,
        help: "produce warnings in a machine parseable format")
    ..addFlag("help", abbr: 'h',
        negatable: false, help: "displays this help and exit");
  var args = parser.parse(arguments);
  if (args["help"]) {
    print('A build script that invokes the web-ui compiler (dwc).');
    print('Usage: dart build.dart [options] [-- [dwc-options]]');
    print('\nThese are valid options expected by build.dart:');
    print(parser.getUsage());
    print('\nThese are valid options expected by dwc:');
    dwc.run(['-h']).then((_) => exit(0));
  }
  return args;
}
