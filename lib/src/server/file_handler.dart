part of server;

class SyncFileLoggingHandler implements BaseLoggingHandler {
  
  LogRecordTransformer transformer;
  final String filename;
  File _file;
  
  SyncFileLoggingHandler(String this.filename, {this.transformer}) {
    if (this.transformer == null) this.transformer = new StringTransformer();
    _file = new File(filename);        
  }
  
  call(LogRecord logRecord) {
    var f = _file.openSync(mode:FileMode.APPEND);
    f.writeStringSync(transformer.transform(logRecord) + "\n");
    f.closeSync();
  }  
}