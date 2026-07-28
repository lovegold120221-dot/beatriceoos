/// Centralized application logger.
///
/// Use [appLogger] everywhere instead of `print`/`debugPrint` so that
/// network failures, parse errors, and service transitions are observable
/// rather than silently swallowed. Output is disabled in release builds
/// unless overridden.
library;

import 'package:logger/logger.dart';

/// Shared [Logger] instance for the whole app.
final Logger appLogger = Logger(
  filter: ProductionFilter(),
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 8,
    lineLength: 100,
    colors: true,
    printEmojis: false,
    dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
  ),
);