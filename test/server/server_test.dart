library server_test;

import 'package:logging_handlers/server_logging_handlers.dart'; 
import 'package:unittest/unittest.dart';
import 'package:logging/logging.dart';
import 'dart:io';

main() {
  testFileSync();
}

void setup(filename) {
  var file = new File(filename);
  if (file.existsSync()) {
    file.deleteSync();
  }  
}


void testFileSync() {
  test('sync file writing', () {
    // setup and write to the file
    var filename = "mylog1.txt";
    setup(filename);
    
    // perform the call under test
    var handler = new SyncFileLoggingHandler(filename);
    var logger = new Logger("mylogger");
    logger.onRecord.listen(handler);
    
    logger.info("Hello World");
    
    //verify the contents of the file
    var file = new File(filename);
    expect(file.existsSync(), isTrue);
    expect(file.readAsStringSync(), contains("[INFO]:\tHello World"));
  });
}

