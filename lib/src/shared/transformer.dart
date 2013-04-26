part of logging_handlers_shared;

/**
 * Base implementation of [LogRecord] formatter.  Simply returns the 
 * original LogRecord with no transformation
 * 
 */
abstract class LogRecordTransformer {
  /**
   * Base implementation simply returns the log record's message
   */
  dynamic transform(LogRecord logRecord) {
    return logRecord;
  }
}



