/// A simple [Result] type so services can return outcomes instead of
/// throwing raw exceptions or silently swallowing failures.
library;

import 'errors/app_exception.dart';

/// Either a successful value of type [T], or a failure carrying an
/// [AppException].
sealed class Result<T> {
  const Result();

  /// `true` when this holds a success value.
  bool get isSuccess => this is Success<T>;

  /// `true` when this holds a failure.
  bool get isFailure => this is Failure<T>;

  /// The success value, or `null` when this is a failure.
  T? get valueOrNull => switch (this) {
        Success<T>(value: final v) => v,
        Failure<T>() => null,
      };

  /// The failure exception, or `null` when this is a success.
  AppException? get errorOrNull => switch (this) {
        Success<T>() => null,
        Failure<T>(error: final e) => e,
      };

  /// Transform the success value, leaving failures untouched.
  Result<R> map<R>(R Function(T value) fn) => switch (this) {
        Success<T>(value: final v) => Success<R>(fn(v)),
        Failure<T>(error: final e) => Failure<R>(e),
      };

  /// Run [onSuccess] / [onFailure] and return the chosen result.
  R when<R>({
    required R Function(T value) onSuccess,
    required R Function(AppException error) onFailure,
  }) => switch (this) {
        Success<T>(value: final v) => onSuccess(v),
        Failure<T>(error: final e) => onFailure(e),
      };
}

/// A successful result carrying [value].
final class Success<T> extends Result<T> {
  const Success(this.value);
  final T value;
}

/// A failed result carrying [error].
final class Failure<T> extends Result<T> {
  const Failure(this.error);
  final AppException error;
}