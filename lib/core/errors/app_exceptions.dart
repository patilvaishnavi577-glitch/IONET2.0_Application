/// Typed application exceptions that provide safe, sanitized user-facing messages
/// while protecting internal API endpoints, server addresses, and database schemas.
abstract class AppException implements Exception {
  final String userMessage;
  final int? statusCode;
  final dynamic technicalDetails;

  const AppException(
    this.userMessage, {
    this.statusCode,
    this.technicalDetails,
  });

  @override
  String toString() => userMessage;
}

/// Thrown when there is no network connection, DNS lookup fails, or socket cannot be opened.
class NetworkException extends AppException {
  const NetworkException([dynamic technicalDetails])
      : super(
          'No internet connection. Please check your network and try again.',
          statusCode: null,
          technicalDetails: technicalDetails,
        );
}

/// Thrown when an HTTP request or connection exceeds the timeout threshold.
class TimeoutAppException extends AppException {
  const TimeoutAppException([dynamic technicalDetails])
      : super(
          'The connection timed out. Please try again.',
          statusCode: 408,
          technicalDetails: technicalDetails,
        );
}

/// Thrown when the server responds with 5xx or returns invalid non-JSON payloads (like HTML error pages).
class ServerAppException extends AppException {
  const ServerAppException({
    int? statusCode,
    String? message,
    dynamic technicalDetails,
  }) : super(
          message ?? 'Server is currently unavailable. Please try again later.',
          statusCode: statusCode ?? 500,
          technicalDetails: technicalDetails,
        );
}

/// Thrown when authentication fails or token expires (HTTP 401).
class UnauthorizedException extends AppException {
  const UnauthorizedException({
    String? message,
    dynamic technicalDetails,
  }) : super(
          message ?? 'Your session has expired. Please log in again.',
          statusCode: 401,
          technicalDetails: technicalDetails,
        );
}

/// Thrown when the user is forbidden from performing the action (HTTP 403).
class ForbiddenException extends AppException {
  const ForbiddenException({
    String? message,
    dynamic technicalDetails,
  }) : super(
          message ?? 'You do not have permission to perform this action.',
          statusCode: 403,
          technicalDetails: technicalDetails,
        );
}

/// Thrown when a resource is not found (HTTP 404).
class NotFoundException extends AppException {
  const NotFoundException({
    String? message,
    dynamic technicalDetails,
  }) : super(
          message ?? 'The requested resource was not found.',
          statusCode: 404,
          technicalDetails: technicalDetails,
        );
}

/// Thrown when validation fails or client sent a bad request (HTTP 400 / 422).
class ValidationException extends AppException {
  const ValidationException(
    super.userMessage, {
    super.statusCode = 400,
    super.technicalDetails,
  });
}

/// Thrown when WebSocket connection or real-time frame transmission fails.
class WebSocketAppException extends AppException {
  const WebSocketAppException([
    String? message,
    dynamic technicalDetails,
  ]) : super(
          message ?? 'Real-time connection interrupted. Reconnecting...',
          statusCode: null,
          technicalDetails: technicalDetails,
        );
}
