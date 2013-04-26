part of logging_handlers_shared;

/**
 * Transforms a Log Record into a Map that can be stringified by JSON.stringify()  
 */
class MapTransformer implements BaseLogRecordTransformer {
  
  /**
   * Convert the logRecord into a map that is parsable by the JSON library
   */
  Map transform(LogRecord logRecord) {
    var map = new Map();
    map["level"] = logRecord.level.name;
    map["message"] = logRecord.message;
    map["time"] = logRecord.time.toString();
    map["sequenceNumber"] = logRecord.sequenceNumber;
    map["loggerName"] = logRecord.loggerName;
    map["exceptionText"] = logRecord.exceptionText;
    if (logRecord.exception != null) {
      map["exception"] = logRecord.exception.toString();
    }
    else {
      map["exception"] = null;
    }    
    return map;
  }
}
