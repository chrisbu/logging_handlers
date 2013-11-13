library browser;

import 'dart:html';
import 'dart:async'; 
import 'logging_handlers_shared.dart';
import 'package:logging/logging.dart';
export 'logging_handlers_shared.dart';

/**
 * Attaches logging handlers to the root logger.
 * Web UI components aren't available until the next
 * iteration of the event loop, so it lives in a Timer.run.
 * Startup items won't be logged.
 */
void attachXLoggerUi([bool addPrintHandler=true]) {
  Timer.run(() {
    var loggerComponents = querySelectorAll("div[is=x-loggerui]");
    print(loggerComponents);
    var listener = Logger.root.onRecord.asBroadcastStream();
    loggerComponents.forEach((component) {
    		var loggerHandler = component.xtag;
    		listener.listen(loggerHandler);
    	});
    
    //optionally attach a default print handler
    if (addPrintHandler) listener.listen(new LogPrintHandler());
  });
}