library shared_test;

import 'package:logging_handlers/logging_handlers_shared.dart'; 
import 'package:unittest/unittest.dart';
import 'package:logging/logging.dart';

part 'src/transformer_tests.dart';

main() {
  
  runTransformerTests();  
  runTopLevelTests();
}


runTopLevelTests() {
  group("top-level", () {
    test("customPrintHandler", () {
      var logger = new Logger("mylogger");
      //logger.onRecord.listen(printHandler(messageFormat:"%m"));
      logger.onRecord.listen(printHandler());
      logger.info("Hello World");  
    });
  });
  
}