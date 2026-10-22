// Generated from the shared API endpoint specification. Do not edit.
abstract final class ApiRoutes {
  static const health = '/api/health';
  static const demo = '/api/auth/demo';
  static const login = '/api/auth/login';
  static const signup = '/api/auth/signup';
  static const bootstrap = '/api/bootstrap';
  static String weather(String id) => '/api/fields/${Uri.encodeComponent(id)}/weather';
  static const uploadPhoto = '/api/photos';
  static String photo(String id) => '/api/photos/${Uri.encodeComponent(id)}';
  static const saveObservation = '/api/observations';
  static String approveObservation(String id) => '/api/observations/${Uri.encodeComponent(id)}/approve';
  static String completeTask(String id) => '/api/tasks/${Uri.encodeComponent(id)}/complete';
  static const chat = '/api/agent/chat';
  static const sync = '/api/sync';
  static String readNotification(String id) => '/api/notifications/${Uri.encodeComponent(id)}/read';
}
