part of logging_handlers_shared;

/**
 * Format a log record according to a string pattern
 */
class StringTransformer implements BaseLogRecordTransformer {
  
  /// Outputs [LogRecord.level]
  static final LEVEL = "%p";  
  
  /// Outputs [LogRecord.message]
  static final MESSAGE = "%m"; 
  
  /// Outputs the [Logger.name]
  static final NAME = "%n"; 
  
  /// Outputs the timestamp according to the Date Time Format specified in
  /// [timestampFormatString]
  static final TIME = "%t"; // logger date timestamp.  Format using
  
  /// Outputs the logger sequence
  static final SEQ = "%s"; // logger sequence
  static final EXCEPTION = "%x"; // logger exception
  static final EXCEPTION_TEXT = "%e"; // logger exception message
  static final TAB = "\t";
  static final NEW_LINE = "\n";
  
  /// Default format for a log message that does not contain an exception.
  static const DEFAULT_MESSAGE_FORMAT = "%t\t%n\t[%p]:\t%m";
  
  /// Default format for a log message the contains an exception
  /// This is appended onto the message format if there is an exception
  static const DEFAULT_EXCEPTION_FORMAT = "\n%e\n%x";
  
  /// Default date time format for log messages
  static const DEFAULT_DATE_TIME_FORMAT = "yyyy.mm.dd HH:mm:ss.SSS Z";
  
  /// Contains the standard message format string
  final String messageFormat;
  
  /// Contains the exception format string
  final String exceptionFormatSuffix;
  
  /// Contains the timestamp format string
  final String timestampFormat;
  
  /// Contains the date format instance
  DateFormat dateFormat;
  
  /// Contains the regexp pattern
  static final _regexp = new RegExp("($LEVEL|$MESSAGE|$NAME|$TIME|$SEQ|$EXCEPTION|$EXCEPTION_TEXT)");
  
  StringTransformer({
      String this.messageFormat : StringTransformer.DEFAULT_MESSAGE_FORMAT,
      String this.exceptionFormatSuffix : StringTransformer.DEFAULT_EXCEPTION_FORMAT, 
      String this.timestampFormat : StringTransformer.DEFAULT_DATE_TIME_FORMAT}) { 
    dateFormat = new DateFormat(this.timestampFormat);
  }
  
  /**
   * Transform the log record into a string according to the [messageFormat], 
   * [exceptionFormatSuffix] and [timestampFormat] pattern.
   */
  String transform(LogRecord logRecord) {
    var formatString = logRecord.exception == null ? 
                                  messageFormat : 
                                  messageFormat+exceptionFormatSuffix;
    
    // build the log string and return
    return formatString.replaceAllMapped(_regexp, (match) {
      if (match.groupCount == 1) {
        switch (match.group(0)) {
          case LEVEL: 
            return logRecord.level.name;
          case MESSAGE:
            return logRecord.message;
          case NAME:
            return logRecord.loggerName;
          case TIME: 
            if (logRecord.time != null) {
              try {
                return dateFormat.format(logRecord.time);
              } 
              on UnimplementedError catch (e) {
                // at time of writing, dateFormat.format seems to be unimplemented.
                // so just return the time.toString()
                return logRecord.time.toString();
              }
            }
            
            break;
          case SEQ:
            return logRecord.sequenceNumber.toString();
          case EXCEPTION: 
            if (logRecord.exception != null) return logRecord.exception.toString();
          case EXCEPTION_TEXT:
            return logRecord.exceptionText;
        }
      }

      return ""; // empty string
    });
  }
  
    
}

