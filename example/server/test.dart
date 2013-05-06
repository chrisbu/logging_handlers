import 'dart:io';
import 'package:logging_handlers/server_logging_handlers.dart';
import 'package:logging/logging.dart';
 
main() {
   var logger = new Logger("mylogger");
   logger.onRecord.listen(new PrintHandler());
   logger.info("Hello World"); // should output to the console
}