// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/**
 * This is a helper for run.sh. We try to run all of the Dart code in one
 * instance of the Dart VM to reduce warm-up time.
 */
library web_ui.testing.render_test;

import 'dart:io';
import 'dart:math' show min;
import 'package:pathos/path.dart' as path;
import 'package:unittest/unittest.dart';
import 'package:web_ui/dwc.dart' as dwc;

void renderTests(String baseDir, String inputDir, String expectedDir,
    String outDir, [List<String> args, String script]) {

  if (args == null) args = new Options().arguments;
  if (script == null) script = new Options().script;

  var pattern = new RegExp(args.length > 0 ? args[0] : '.');

  var scriptDir = path.absolute(path.dirname(script));
  baseDir = path.join(scriptDir, baseDir);
  inputDir = path.join(scriptDir, inputDir);
  expectedDir = path.join(scriptDir, expectedDir);
  outDir = path.join(scriptDir, outDir);

  var paths = new Directory(inputDir).listSync()
      .where((f) => f is File).map((f) => f.path)
      .where((p) => p.endsWith('_test.html') && pattern.hasMatch(p));

  // First clear the output folder. Otherwise we can miss bugs when we fail to
  // generate a file.
  var dir = new Directory(outDir);
  if (dir.existsSync()) {
    print('Cleaning old output for ${path.normalize(outDir)}');
    dir.deleteSync(recursive: true);
  }
  dir.createSync();

  for (var filePath in paths) {
    var filename = path.basename(filePath);
    test('drt-compile $filename', () {
      expect(dwc.run(['-o', outDir, '--basedir', baseDir, filePath],
        printTime: false)
        .then((res) {
          expect(res.messages.length, 0, reason: res.messages.join('\n'));
        }), completes);
    });
  }

  if (!paths.isEmpty) {
    var filenames = paths.map(path.basename).toList();
    // Sort files to match the order in which run.sh runs diff.
    filenames.sort();
    var outs;

    // Get the path from "input" relative to "baseDir"
    var relativeToBase = path.relative(inputDir, from: baseDir);

    test('drt-run', () {
      var inputUrls = filenames.map((name) =>
          'file://${path.join(outDir, relativeToBase, name)}').toList();

      expect(Process.run('DumpRenderTree', inputUrls).then((res) {
        expect(res.exitCode, 0, reason: 'DumpRenderTree exit code: '
          '${res.exitCode}. Contents of stderr: \n${res.stderr}');
        outs = res.stdout.split('#EOF\n')
          .where((s) => !s.trim().isEmpty).toList();
        expect(outs.length, filenames.length);
      }), completes);
    });

    for (int i = 0; i < filenames.length; i++) {
      var filename = filenames[i];
      // TODO(sigmund): remove this extra variable dartbug.com/8698
      int j = i;
      test('verify $filename', () {
        expect(outs, isNotNull, reason:
          'Output not available, maybe DumpRenderTree failed to run.');
        var output = outs[j];
        var outPath = path.join(outDir, '$filename.txt');
        var expectedPath = path.join(expectedDir, '$filename.txt');
        new File(outPath).writeAsStringSync(output);
        var expected = new File(expectedPath).readAsStringSync();
        expect(output, new SmartStringMatcher(expected),
          reason: 'unexpected output for <$filename>');
      });
    }
  }
}

// TODO(jmesserly): we need a full diff tool.
// TODO(sigmund): consider moving this matcher to unittest
class SmartStringMatcher extends BaseMatcher {
  final String _value;

  SmartStringMatcher(this._value);

  bool matches(item, MatchState mismatchState) => _value == item;

  Description describe(Description description) =>
      description.addDescriptionOf(_value);

  Description describeMismatch(item, Description mismatchDescription,
      MatchState matchState, bool verbose) {
    if (item is! String) {
      return mismatchDescription.addDescriptionOf(item).add(' not a string');
    } else {
      var buff = new StringBuffer();
      buff.write('Strings are not equal.');
      var escapedItem = _escape(item);
      var escapedValue = _escape(_value);
      int minLength = min(escapedItem.length, escapedValue.length);
      int start;
      for (start = 0; start < minLength; start++) {
        if (escapedValue.codeUnitAt(start) != escapedItem.codeUnitAt(start)) {
          break;
        }
      }
      if (start == minLength) {
        if (escapedValue.length < escapedItem.length) {
          buff.write(' Both strings start the same, but the given value also'
              ' has the following trailing characters: ');
          _writeTrailing(buff, escapedItem, escapedValue.length);
        } else {
          buff.write(' Both strings start the same, but the given value is'
              ' missing the following trailing characters: ');
          _writeTrailing(buff, escapedValue, escapedItem.length);
        }
      } else {
        buff.write('\nExpected: ');
        _writeLeading(buff, escapedValue, start);
        buff.write('[32m');
        buff.write(escapedValue[start]);
        buff.write('[0m');
        _writeTrailing(buff, escapedValue, start + 1);
        buff.write('\n But was: ');
        _writeLeading(buff, escapedItem, start);
        buff.write('[31m');
        buff.write(escapedItem[start]);
        buff.write('[0m');
        _writeTrailing(buff, escapedItem, start + 1);
        buff.write('[32;1m');
        buff.write('\n          ');
        for (int i = (start > 10 ? 14 : start); i > 0; i--) buff.write(' ');
        buff.write('^  [0m');
      }

      return mismatchDescription.replace(buff.toString());
    }
  }

  static String _escape(String s) =>
      s.replaceAll('\n', '\\n').replaceAll('\r', '\\r').replaceAll('\t', '\\t');

  static String _writeLeading(StringBuffer buff, String s, int start) {
    if (start > 10) {
      buff.write('... ');
      buff.write(s.substring(start - 10, start));
    } else {
      buff.write(s.substring(0, start));
    }
  }

  static String _writeTrailing(StringBuffer buff, String s, int start) {
    if (start + 10 > s.length) {
      buff.write(s.substring(start));
    } else {
      buff.write(s.substring(start, start + 10));
      buff.write(' ...');
    }
  }
}
