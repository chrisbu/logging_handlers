library loggerui;

import 'dart:html';
import 'package:web_ui/web_ui.dart';
import 'package:web_ui/watcher.dart' as watcher;
import 'package:logging/logging.dart';
import 'package:logging_handlers/logging_handlers_shared.dart';

class LoggerUi extends WebComponent implements BaseLoggingHandler {
  List<LogRecord> logRecords = new List<LogRecord>();
  
  List<String> messages = new List<String>();

  LoggerUi() {
    transformer = new StringTransformer();
  }
  
  LogRecordTransformer transformer;
  
  void call(LogRecord logRecord) {
    logRecords.add(logRecord);
    messages.add(transformer.transform(logRecord));
    watcher.dispatch();
  }
  
}