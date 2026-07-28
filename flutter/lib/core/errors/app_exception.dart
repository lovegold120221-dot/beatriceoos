/// Structured application exceptions.
///
/// Replaces raw `catch (e) { return e.toString(); }` patterns so callers can
/// branch on cause instead of parsing strings.
library;

/// Base type for every Beatrice domain error.
class AppException implements Exception {
  const AppException(this.message, {this.cause, this.stackTrace});

  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => '$runtimeType: $message';
}

/// The device has no network connectivity, or the request could not reach
/// the server at all.
class NetworkException extends AppException {
  const NetworkException(super.message, {super.cause, super.stackTrace});
}

/// The server responded with an error status code.
class ApiException extends AppException {
  const ApiException(this.statusCode, super.message, {this.body, super.cause, super.stackTrace});

  /// HTTP status code returned by the server (or -1 when unavailable).
  final int statusCode;

  /// Raw response body (string or decoded JSON), when available.
  final Object? body;

  /// 429 Too Many Requests / rate limited.
  bool get isRateLimited => statusCode == 429;

  /// 5xx server error.
  bool get isServerError => statusCode >= 500 && statusCode < 600;
}

/// A network or service operation timed out.
class TimeoutException extends AppException {
  const TimeoutException(super.message, {super.cause, super.stackTrace});
}

/// Authentication failed (bad credentials, expired token, etc.).
class AuthException extends AppException {
  const AuthException(super.message, {super.cause, super.stackTrace});
}

/// Decoding a model/JSON payload failed.
class ParseException extends AppException {
  const ParseException(super.message, {super.cause, super.stackTrace});
}

/// Coerce any [Object] into an [AppException], preserving the original as the
/// cause.
AppException toAppException(Object error, [StackTrace? stack]) {
  if (error is AppException) return error;
  return AppException(error.toString(), cause: error, stackTrace: stack);
}