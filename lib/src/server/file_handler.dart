part of server;

class FileLoggingHandler implements BaseLoggingHandler {
  
  LogRecordTransformer transformer;
  final String filename;
  File _file;
  IOSink _sink;
  
  FileLoggingHandler(String this.filename, {this.transformer}) {
    if (this.transformer == null) this.transformer = new StringTransformer();
    _file = new File(filename);
    _sink = _file.openWrite(mode:FileMode.APPEND);
  }
  
  call(LogRecord logRecord) {
     _sink.writeln(transformer.transform(logRecord));     
  }  
}