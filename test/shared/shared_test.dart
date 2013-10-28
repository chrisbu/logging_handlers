library shared_test;

import 'package:logging_handlers/logging_handlers_shared.dart'; 
import 'package:unittest/unittest.dart';
import 'package:logging/logging.dart';
import 'dart:convert';

part 'src/transformer_tests.dart';

main() {
  
  runTransformerTests();  
  runTopLevelTests();
}


runTopLevelTests() {
  group("top-level", () {
    
    test("customPrintHandler", () {
      var logger = new Logger("mylogger");
      var printed = "";
      var printFunc = (value) => printed = value;
      logger.onRecord.listen(new PrintHandler(messageFormat:"%m", printFunc:printFunc));
      logger.info("Hello World");
      expect(printed, equals("Hello World"));
    });
    
    test("defaultPrintHandler", () {
      var logger = new Logger("mylogger");
      var printed = "";
      var printFunc = (value) => printed = value;
      logger.onRecord.listen(new PrintHandler(printFunc:printFunc));
      //logger.onRecord.listen(printHandler(printFunc:printFunc));
      logger.info("Hello World");
      // contains, rather than equals, because it contains the always-changing timestamp
      expect(printed, contains("\tmylogger\t[INFO]:\tHello World"));
    });
    
    test("quick n dirty", () {
      startQuickLogging();
      info("I'm a quick n dirty log message");
    });
  });
  
  
  
}