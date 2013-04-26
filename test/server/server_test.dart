library server_test;

import 'package:logging_handlers/server_logging_handlers.dart'; 
import 'package:unittest/unittest.dart';
import 'package:logging/logging.dart';

main() {
  var filename = "mylog.txt";
  var handler = new FileLoggingHandler("mylog.txt");
  var logger = new Logger("mylogger");
  logger.onRecord.listen(handler);
  for (int i=0; i < 100000; i++) {
    logger.info("Hello World $i");
  }
}
