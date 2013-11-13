import 'dart:html';
import 'package:logging_handlers/browser_logging_handlers.dart';
import 'package:logging/logging.dart';
import 'dart:async'; 

main() {
   hierarchicalLoggingEnabled = true;
   Logger.root.level = Level.OFF;
   var logger = new Logger("mylogger")..level = Level.ALL;
   new Logger("loggerui");//..level = Level.ALL;
   
   
   attachXLoggerUi();
   
   
   querySelector("#click").onClick.listen((_) {
     logger.info("Button clicked");
     debug("Foo", "loggerui");
   });
   
 }