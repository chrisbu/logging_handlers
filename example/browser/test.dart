import 'dart:html';
import 'package:logging_handlers/browser_logging_handlers.dart';
import 'package:logging/logging.dart';
import 'dart:async'; 

main() {
   //hierarchicalLoggingEnabled = true;
   var logger = new Logger("mylogger")..level = Level.ALL;
   var loggerui = new Logger("loggerui")..level = Level.INFO;
   Logger.root.level = Level.ALL;
   Timer.run(() {
     var loggerComponent = query("#loggerui");
     var loggerHandler = loggerComponent.xtag;
     
     var listener = Logger.root.onRecord.asBroadcastStream();
     listener.listen(loggerHandler);
     listener.listen(new PrintHandler());
     logger.warning("Hello World"); // should output to the console       
   });
   
   
   query("#click").onClick.listen((_) {
     logger.fine("Button clicked");
     loggerui.finest("Foo");
     
   });
   
 }