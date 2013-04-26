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
    
    group("JsonTransformer", () {
      runJsonTransformerTests();
    });

  });
}


class TestFormatterImpl extends BaseLogRecordTransformer { }


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
    var logRecordNoException = new LogRecord(Level.INFO, 
        message, 
        loggerName,
        time);
    var logRecordWithException = new LogRecord(Level.INFO, 
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
        contains(" 27-02-2012 my.logger[INFO]: I am a message"));
    expect(impl.transform(logRecordWithException),
        contains(" 27-02-2012 my.logger[INFO]: I am a message Exception text Exception: I am an exception"));
    
  });  
}

runJsonTransformerTests() {
  
}