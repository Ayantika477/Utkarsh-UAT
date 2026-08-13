public with sharing class BWM_MessagingDebugLogger {
  private static List<String> traceLines = new List<String>();

  public static void trace(
    String hypothesisId,
    String location,
    String message,
    Map<String, Object> data
  ) {
    Map<String, Object> entry = new Map<String, Object>{
      'sessionId' => 'b457e3',
      'hypothesisId' => hypothesisId,
      'location' => location,
      'message' => message,
      'data' => data == null ? new Map<String, Object>() : data,
      'timestamp' => System.now().getTime()
    };
    traceLines.add(JSON.serialize(entry));
  }

  public static String flushTrace() {
    if (traceLines.isEmpty()) {
      return null;
    }
    String combined = String.join(traceLines, '\n');
    traceLines.clear();
    return combined;
  }

  @TestVisible
  static void clearForTest() {
    traceLines.clear();
  }
}