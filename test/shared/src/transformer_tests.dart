part of shared_test;

class MockStackTrace extends Mock implements StackTrace {
  String _text;
  MockStackTrace(String this._text);
  toString() => _text;
}

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
  print(new MockStackTrace("Exception text").toString());
  test("defaults", () {
    var message = "I am a message";
    var loggerName = "my.logger";
    //var time = DateTime.parse("2012-02-27 13:27:00.123456z");
    var time = new DateTime.now();
    var formatter = new DateFormat('yyyy-MM-dd');
    var logRecord = new LogRecord(Level.INFO, message, loggerName);
    
    var impl = new StringTransformer();
    expect(impl.transform(logRecord),
        contains("\tmy.logger\t[INFO]:\tI am a message"));
    expect(impl.transform(logRecord),
        startsWith(formatter.format(time)));
  });
  
  test("defaults with exception", () {
    var message = "I am a message";
    var loggerName = "my.logger";
    //var time = DateTime.parse("2012-02-27 13:27:00.123456z");
    var time = new DateTime.now();
    var formatter = new DateFormat('yyyy-MM-dd');
    var exception = new Exception("I am an exception");
    var logRecord = new LogRecord(Level.INFO, 
        message, 
        loggerName, 
        exception,
        new MockStackTrace("Exception text"));
    
    var impl = new StringTransformer();
    expect(impl.transform(logRecord),
        contains("\tmy.logger\t[INFO]:\tI am a message\nException text\nException: I am an exception"));
    expect(impl.transform(logRecord),
        startsWith(formatter.format(time)));
  });  
  
  test("custom formats", () {
    var message = "I am a message";
    var loggerName = "my.logger";
    //var time = DateTime.parse("2012-02-27 13:27:00.123456z");
    var time = new DateTime.now();
    var formatter = new DateFormat('dd-MM-yyyy');
    var exception = new Exception("I am an exception");
    var logRecordNoException = new LogRecord(Level.FINEST, 
        message, 
        loggerName);
    var logRecordWithException = new LogRecord(Level.FINEST, 
        message, 
        loggerName, 
        exception,
        new MockStackTrace("Exception text"));
    
    var impl = new StringTransformer(messageFormat: "%s %t %n[%p]: %m", exceptionFormatSuffix: " %e %x", timestampFormat: "dd-MM-yyyy");
    // Note - this prints the exception message with a sequence number.
    // The sequence number is unique, and depends where about this test falls in 
    // relation to other tests.  For that reason, we'll check that the logged
    // output "contains" the expected string without the sequence number prefix 
    expect(impl.transform(logRecordNoException),
        contains(" ${formatter.format(time)} my.logger[FINEST]: I am a message"));
    expect(impl.transform(logRecordWithException),
        contains(" ${formatter.format(time)} my.logger[FINEST]: I am a message Exception text Exception: I am an exception"));
    
  });  
}

runMapTransformerTests() {
  test("defaults", () {
    var message = "I am a message";
    var loggerName = "my.logger";
    var logRecord = new LogRecord(Level.INFO, message, loggerName);
    
    var impl = new MapTransformer();
    var map = impl.transform(logRecord); // convert the logRecord to a map    
    String json = JSON.encode(map); // convert the map to json with dart:convert
    Map map2 = JSON.decode(json); // convert the json back to a map
    
    expect(map2["message"], equals(logRecord.message));
    expect(map2["loggerName"], equals(logRecord.loggerName));
    expect(map2["level"], equals(logRecord.level.name));
    expect(map2["sequenceNumber"], equals(logRecord.sequenceNumber));
    expect(map2["stackTrace"], isNull);
    expect(map2["error"], isNull);
    expect(map2["time"], equals(logRecord.time.toString()));
    
  });
  
  test("defaults with exception", () {
    var message = "I am a message";
    var loggerName = "my.logger";
    var exception = new Exception("I am an exception");
    var logRecord = new LogRecord(Level.INFO, 
        message, 
        loggerName, 
        exception,
        new MockStackTrace("Exception text"));
    
    var impl = new MapTransformer();
    var map = impl.transform(logRecord); // convert the logRecord to a map    
    String json = JSON.encode(map); // convert the map to json with dart:convert
    Map map2 = JSON.decode(json); // convert the json back to a map
    
    expect(map2["message"], equals(logRecord.message));
    expect(map2["loggerName"], equals(logRecord.loggerName));
    expect(map2["level"], equals(logRecord.level.name));
    expect(map2["sequenceNumber"], equals(logRecord.sequenceNumber));
    expect(map2["stackTrace"], equals(logRecord.stackTrace.toString()));
    expect(map2["error"], equals(logRecord.error.toString()));
    expect(map2["time"], equals(logRecord.time.toString()));
  });  
}