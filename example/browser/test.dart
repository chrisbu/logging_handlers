import 'dart:html';
import 'package:logging_handlers/browser_logging_handlers.dart';
import 'package:logging/logging.dart';
import 'dart:async'; 

main() {
   var logger = new Logger("mylogger");
   Timer.run(() {
     var loggerComponent = query("#loggerui");
     var loggerHandler = loggerComponent.xtag;
     
     var listener = logger.onRecord.asBroadcastStream();
     listener.listen(loggerHandler);
     listener.listen(new PrintHandler());
     logger.warning("Hello World"); // should output to the console       
   });
   
   
   query("#click").onClick.listen((_) {
     logger.info("Button clicked");
   });
   
 }