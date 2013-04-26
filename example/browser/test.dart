import 'dart:html';
import 'package:logging_handlers/browser_logging_handlers.dart';
import 'package:logging/logging.dart';
 
main() {
   var logger = new Logger("mylogger");
   logger.onRecord.listen(printHandler());
   logger.info("Hello World"); // should output to the console
 }