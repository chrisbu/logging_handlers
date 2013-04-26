library logging_handlers_shared;

import 'dart:json';

import 'package:logging/logging.dart';
import 'package:intl/intl.dart';

part 'src/shared/transformer.dart';
part 'src/shared/string_transformer.dart';
part 'src/shared/map_transformer.dart';

var _stringTransformer = new StringTransformer();


/**
 * Creates a default handler that ouputs using the build-in [print] function.
 * 
 * Example usage, with custom message formatting to make it look like the
 * standard print() output:
 * 
 *     import 'package:logging_handlers/logging_handlers_shared.dart';
 *     import 'package:logging/logging.dart';
 * 
 *     main() {
 *       var logger = new Logger("mylogger");
 *       logger.onRecord.listen(new PrintHandler(messageFormat:"%m"));
 *       logger.info("Hello World"); // same as: print("Hello World");
 *     }
 *     
 *  If you just pass in the output of the `printHandler()` function itself, 
 *  then you get the defalut message formatting, for example
 *  
 *     var logger = new Logger("mylogger");
 *     logger.onRecord.listen(new PrintHandler());
 *     logger.info("Hello World"); 
 *     // 2013-04-26 11:50:40.506 mylogger  [INFO]: Hello World
 *   
 *  The [PrintHandler] consutrctor takes the following optional parameters:
 *  
 *  - [messageFormat] - The format string for log messages.  
 *    This defaults to [StringTransformer.DEFAULT_MESSAGE_FORMAT].
 *  - [exceptionFormatSuffix] - The format string that is appended to the 
 *    [messageFormat] if the log record contains an exception.  This defaults
 *    to [StringTransformer.DEFAULT_EXCEPTION_FORMAT]
 *  - [timestampFormat] to let you format the log timestamp.  This defaults to
 *    [StringTransformer.DEFAULT_DATE_TIME_FORMAT].
 *  - [printFunc] to allow a custom print function to be passed in (primarily to
 *    ease unit testing of this function).  This defaults to the 
 *    standard dart [print] function.  
 *   
 *  Check out the [StringTransformer] class for possible format strings.
 *  
 */
class PrintHandler implements BaseLoggingHandler {
  
  var _transformer;
  String messageFormat;
  String exceptionFormatSuffix;
  String timestampFormat;
  Function printFunc;
  
  PrintHandler({
    this.messageFormat: StringTransformer.DEFAULT_MESSAGE_FORMAT, 
    this.exceptionFormatSuffix: StringTransformer.DEFAULT_EXCEPTION_FORMAT, 
    this.timestampFormat: StringTransformer.DEFAULT_DATE_TIME_FORMAT,
    this.printFunc: print}) {
    _transformer = new StringTransformer(
        messageFormat: messageFormat, 
        exceptionFormatSuffix: exceptionFormatSuffix, 
        timestampFormat: timestampFormat);
  }
  
  void call(LogRecord logRecord) {
    printFunc(_transformer.transform(logRecord));
  }
}


/**
 * A base logging handler class that can be psassed into the 
 * logger.onRecord.listen() handler.
 */
abstract class BaseLoggingHandler {
  void call(LogRecord logRecord);
}