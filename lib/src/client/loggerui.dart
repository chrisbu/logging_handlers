library loggerui;

import 'package:polymer/polymer.dart';
import 'package:logging/logging.dart';
import 'package:logging_handlers/logging_handlers_shared.dart';

@CustomTag('log-loggerui')
class LoggerUi extends PolymerElement {
  List<LogRecord> logRecords = toObservable(new List<LogRecord>());
  
  List<String> messages = toObservable(new List<String>());

  final _logger = new Logger("loggerui");
  
  LoggerUi.created() : super.created();
  
  LogRecordTransformer transformer = new StringTransformer();
  
  void call(LogRecord logRecord) {
    if (logRecord.loggerName != "loggerui") _logger.finest("adding logrecord"); // don;t log our own records
    logRecords.add(logRecord);
    messages.add(transformer.transform(logRecord));
    if (logRecord.loggerName != "loggerui") _logger.finest("logrecord added");
  }
  
}