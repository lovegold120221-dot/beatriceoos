/// Shared HTTP client for all Beatrice network calls.
///
/// Replaces the per-call `dart:io HttpClient` and `package:http` usages with a
/// single [Dio] instance that provides:
/// - connect/receive timeouts (from [AppConstants]),
/// - automatic retries with exponential backoff for transient failures
///   (timeouts, 429, 5xx) on idempotent requests,
/// - structured [AppException] errors instead of raw throws,
/// - centralized request/response logging,
/// - fast-fail when the device is offline (via [ConnectivityController]).
library;

import 'package:dio/dio.dart';

import '../constants.dart';
import '../errors/app_exception.dart';
import '../logger.dart';
import 'connectivity_controller.dart';

/// Callback used by [ApiClient] to determine whether the device is online.
typedef OnlineChecker = bool Function();

/// Thrown when a request is attempted while offline.
class _OfflineCheckException extends NetworkException {
  _OfflineCheckException() : super('Device is offline');
}

/// A single shared HTTP client.
class ApiClient {
  ApiClient({
    Dio? dio,
    ConnectivityController? connectivity,
    int maxRetries = 3,
  })  : _connectivity = connectivity {
    _dio = dio ?? Dio(
      BaseOptions(
        connectTimeout: const Duration(milliseconds: AppConstants.connectionTimeoutMs),
        receiveTimeout: const Duration(milliseconds: AppConstants.connectionTimeoutMs * 3),
        sendTimeout: const Duration(milliseconds: AppConstants.connectionTimeoutMs * 3),
        responseType: ResponseType.json,
        validateStatus: (_) => true, // we handle status codes ourselves
      ),
    );
    _dio.interceptors.add(_RetryInterceptor(
      dio: _dio,
      maxRetries: maxRetries,
      isOffline: _isOffline,
    ));
    _dio.interceptors.add(_LoggingInterceptor());
    _dio.interceptors.add(_ConnectivityInterceptor(isOffline: _isOffline));
  }

  ConnectivityController? _connectivity;
  late final Dio _dio;

  /// Whether the device is currently considered offline.
  bool _isOffline() {
    final c = _connectivity;
    if (c == null) return false;
    return !c.isOnline;
  }

  /// The underlying [Dio] instance (for advanced callers / adapters in tests).
  Dio get dio => _dio;

  /// Replace the connectivity controller (so [main.dart] can wire a shared
  /// controller after constructing the singleton services).
  set connectivity(ConnectivityController? controller) => _connectivity = controller;

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? headers,
    CancelToken? cancelToken,
  }) =>
      _call(() => _dio.get<T>(
            path,
            queryParameters: query,
            options: Options(headers: headers),
            cancelToken: cancelToken,
          ));

  Future<Response<T>> post<T>(
    String path, {
    Object? body,
    Map<String, dynamic>? headers,
    CancelToken? cancelToken,
  }) =>
      _call(() => _dio.post<T>(
            path,
            data: body,
            options: Options(headers: headers),
            cancelToken: cancelToken,
          ));

  /// Run a dio thunk and translate failures into [AppException].
  Future<Response<T>> _call<T>(Future<Response<T>> Function() thunk) async {
    try {
      if (_isOffline()) throw _OfflineCheckException();
      return await thunk();
    } on DioException catch (e, s) {
      throw _mapDioException(e, s);
    } on AppException {
      rethrow;
    } catch (e, s) {
      throw toAppException(e, s);
    }
  }

  AppException _mapDioException(DioException e, StackTrace s) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return TimeoutException('Request timed out: ${e.message ?? e.type}', cause: e, stackTrace: s);
      case DioExceptionType.connectionError:
        return NetworkException('Connection error: ${e.message ?? e.type}', cause: e, stackTrace: s);
      case DioExceptionType.cancel:
        return NetworkException('Request cancelled', cause: e, stackTrace: s);
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode ?? -1;
        return ApiException(code, _extractErrorMessage(e.response) ?? 'Bad response', body: e.response?.data, cause: e, stackTrace: s);
      case DioExceptionType.unknown:
      case DioExceptionType.badCertificate:
        return NetworkException('Unknown network error: ${e.message}', cause: e, stackTrace: s);
    }
  }

  String? _extractErrorMessage(Response<dynamic>? response) {
    final data = response?.data;
    if (data is Map) {
      final err = data['error'] ?? data['message'] ?? data['detail'];
      if (err is String && err.isNotEmpty) return err;
      if (err is Map && err['message'] is String) return err['message'] as String;
    }
    if (data is String && data.isNotEmpty) return data;
    return null;
  }
}

/// Retries idempotent and explicitly-retryable requests on transient errors.
class _RetryInterceptor extends Interceptor {
  _RetryInterceptor({
    required this.dio,
    required this.maxRetries,
    required this.isOffline,
  });

  final Dio dio;
  final int maxRetries;
  final OnlineChecker isOffline;

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final extra = _extraOf(err.requestOptions);
    final attempt = (extra['attempt'] as int?) ?? 0;

    if (attempt >= maxRetries || !_isRetryable(err) || isOffline()) {
      return handler.next(err);
    }

    final delay = _backoffDelay(attempt, err);
    appLogger.w('Retrying request (${attempt + 1}/$maxRetries) after ${delay.inMilliseconds}ms: ${err.requestOptions.uri}');
    await Future<void>.delayed(delay);

    try {
      final response = await dio.fetch<dynamic>(err.requestOptions.copyWith(
        extra: {...err.requestOptions.extra, 'attempt': attempt + 1},
      ));
      return handler.resolve(response);
    } on DioException catch (e) {
      return handler.next(e);
    }
  }

  bool _isRetryable(DioException err) {
    final method = err.requestOptions.method.toUpperCase();
    final idempotent = method == 'GET' || method == 'HEAD' || method == 'OPTIONS';
    final explicitlyRetryable = (err.requestOptions.extra['retryable'] as bool?) ?? false;
    if (!idempotent && !explicitlyRetryable) return false;

    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badResponse:
        final code = err.response?.statusCode ?? 0;
        return code == 429 || (code >= 500 && code < 600);
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return false;
    }
  }

  Duration _backoffDelay(int attempt, DioException err) {
    // Respect Retry-After when present (seconds).
    final retryAfter = err.response?.headers.value('retry-after');
    if (retryAfter != null) {
      final seconds = int.tryParse(retryAfter);
      if (seconds != null) return Duration(seconds: seconds);
    }
    return Duration(milliseconds: 500 * (1 << attempt)); // 0.5s, 1s, 2s, ...
  }

  Map<String, dynamic> _extraOf(RequestOptions options) => options.extra;
}

/// Fails fast with a [NetworkException] when the device is offline.
class _ConnectivityInterceptor extends Interceptor {
  _ConnectivityInterceptor({required this.isOffline});

  final OnlineChecker isOffline;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (isOffline()) {
      return handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          message: 'Device is offline',
          error: _OfflineCheckException(),
        ),
      );
    }
    handler.next(options);
  }
}

/// Logs every request and the outcome (warn on errors) via [appLogger].
class _LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    appLogger.d('→ ${options.method} ${options.uri}');
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    if (response.statusCode != null && response.statusCode! >= 400) {
      appLogger.w('← ${response.statusCode} ${response.requestOptions.uri}');
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    appLogger.w('✗ ${err.requestOptions.method} ${err.requestOptions.uri} — ${err.type}', error: err.error);
    handler.next(err);
  }
}
