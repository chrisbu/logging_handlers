part of shared_test;



runTransformerTests() {
  group("transformers", () {
    test("BaseLogRecordTransformer", () {
      var impl = new TestFormatterImpl();
      var message = "I am a message";
      var loggerName = "my.logger";
      var logRecord = new LogRecord(Level.INFO, message, loggerName);

      // tests the base transformer.  Expect the same log record to be returned
      expect(impl.transform(logRecord), equals(logRecord)); // expect to get the same output as input
      
    });
    
    group("StringTransformer", () {
      runStringTransformerTests();
    });
    
    group("MapTransformer", () {
      runMapTransformerTests();
    });

  });
}


class TestFormatterImpl extends LogRecordTransformer { }


runStringTransformerTests() {
  test("defaults", () {
    var message = "I am a message";
    var loggerName = "my.logger";
    var time = DateTime.parse("2012-02-27 13:27:00.123456z");
    var logRecord = new LogRecord(Level.INFO, message, loggerName, time);
    
    var impl = new StringTransformer();
    expect(impl.transform(logRecord),
        equals("2012-02-27 13:27:00.123Z\tmy.logger\t[INFO]:\tI am a message"));
  });
  
  test("defaults with exception", () {
    var message = "I am a message";
    var loggerName = "my.logger";
    var time = DateTime.parse("2012-02-27 13:27:00.123456z");
    var exception = new Exception("I am an exception");
    var logRecord = new LogRecord(Level.INFO, 
        message, 
        loggerName, 
        time, 
        exception,
        "Exception text");
    
    var impl = new StringTransformer();
    expect(impl.transform(logRecord),
        equals("2012-02-27 13:27:00.123Z\tmy.logger\t[INFO]:\tI am a message\nException text\nException: I am an exception"));
  });  
  
  test("custom formats", () {
    var message = "I am a message";
    var loggerName = "my.logger";
    var time = DateTime.parse("2012-02-27 13:27:00.123456z");
    var exception = new Exception("I am an exception");
    var logRecordNoException = new LogRecord(Level.FINEST, 
        message, 
        loggerName,
        time);
    var logRecordWithException = new LogRecord(Level.FINEST, 
        message, 
        loggerName, 
        time, 
        exception,
        "Exception text");
    
    var impl = new StringTransformer(messageFormat: "%s %t %n[%p]: %m", exceptionFormatSuffix: " %e %x", timestampFormat: "dd-MM-yyyy");
    // Note - this prints the exception message with a sequence number.
    // The sequence number is unique, and depends where about this test falls in 
    // relation to other tests.  For that reason, we'll check that the logged
    // output "contains" the expected string without the sequence number prefix 
    expect(impl.transform(logRecordNoException),
        contains(" 27-02-2012 my.logger[FINEST]: I am a message"));
    expect(impl.transform(logRecordWithException),
        contains(" 27-02-2012 my.logger[FINEST]: I am a message Exception text Exception: I am an exception"));
    
  });  
}

runMapTransformerTests() {
  test("defaults", () {
    var message = "I am a message";
    var loggerName = "my.logger";
    var time = DateTime.parse("2012-02-27 13:27:00.123456z");
    var logRecord = new LogRecord(Level.INFO, message, loggerName, time);
    
    var impl = new MapTransformer();
    var map = impl.transform(logRecord); // convert the logRecord to a map    
    String json = stringify(map); // convert the map to json with dart:json
    Map map2 = parse(json); // convert the json back to a map
    
    expect(map2["message"], equals(logRecord.message));
    expect(map2["loggerName"], equals(logRecord.loggerName));
    expect(map2["level"], equals(logRecord.level.name));
    expect(map2["sequenceNumber"], equals(logRecord.sequenceNumber));
    expect(map2["exceptionText"], isNull);
    expect(map2["exception"], isNull);
    expect(map2["time"], equals(logRecord.time.toString()));
    
  });
  
  test("defaults with exception", () {
    var message = "I am a message";
    var loggerName = "my.logger";
    var time = DateTime.parse("2012-02-27 13:27:00.123456z");
    var exception = new Exception("I am an exception");
    var logRecord = new LogRecord(Level.INFO, 
        message, 
        loggerName, 
        time, 
        exception,
        "Exception text");
    
    var impl = new MapTransformer();
    var map = impl.transform(logRecord); // convert the logRecord to a map    
    String json = stringify(map); // convert the map to json with dart:json
    Map map2 = parse(json); // convert the json back to a map
    
    expect(map2["message"], equals(logRecord.message));
    expect(map2["loggerName"], equals(logRecord.loggerName));
    expect(map2["level"], equals(logRecord.level.name));
    expect(map2["sequenceNumber"], equals(logRecord.sequenceNumber));
    expect(map2["exceptionText"], equals(logRecord.exceptionText));
    expect(map2["exception"], equals(logRecord.exception.toString()));
    expect(map2["time"], equals(logRecord.time.toString()));
  });  
}