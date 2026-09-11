import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'app_exceptions.dart';

/// Centralized error parser and sanitizer.
///
/// Converts any low-level, OS, network, or server error into a user-safe [AppException]
/// to prevent leaking sensitive API endpoints, IP addresses, database details, or stack traces.
class ErrorHandler {
  ErrorHandler._();

  /// Maps any thrown error or exception to a sanitized [AppException].
  static AppException handle(dynamic error, [StackTrace? stackTrace]) {
    if (kDebugMode) {
      debugPrint('--> [ErrorHandler] Caught: $error');
      if (stackTrace != null) {
        debugPrint('--> [ErrorHandler] StackTrace: $stackTrace');
      }
    }

    if (error is AppException) {
      return error;
    }

    if (error is SocketException) {
      return NetworkException(error.message);
    }

    if (error is TimeoutException) {
      return TimeoutAppException(error.message);
    }

    if (error is FormatException) {
      return const ServerAppException(
        message: 'Received an invalid response format from server.',
      );
    }

    if (error is HandshakeException || error is CertificateException) {
      return const NetworkException('Secure connection could not be established.');
    }

    if (error is HttpException) {
      return const NetworkException('Network communication error.');
    }

    if (error is http.ClientException) {
      final message = error.message.toLowerCase();
      if (message.contains('failed host lookup') ||
          message.contains('connection refused') ||
          message.contains('network is unreachable') ||
          message.contains('socketexception') ||
          message.contains('os error') ||
          message.contains('xmlhttprequest error') ||
          message.contains('connection closed')) {
        return NetworkException(error.message);
      }
      return const NetworkException();
    }

    final rawString = error.toString().replaceAll('Exception: ', '').trim();

    // Check if the raw string contains technical leakage (URLs, internal hosts, DB errors)
    if (_containsTechnicalLeakage(rawString)) {
      return const ServerAppException(
        message: 'Something went wrong. Please try again later.',
      );
    }

    // Common network error strings
    final lower = rawString.toLowerCase();
    if (lower.contains('failed host lookup') ||
        lower.contains('network') ||
        lower.contains('socket') ||
        lower.contains('connection refused')) {
      return const NetworkException();
    }

    if (lower.contains('timeout')) {
      return const TimeoutAppException();
    }

    // If it's a plain, user-safe error message from the backend or validation
    return ValidationException(sanitizeMessage(rawString));
  }

  /// Parses an HTTP response. If successful (2xx), decodes the JSON body.
  /// If unsuccessful or malformed, maps to an appropriate [AppException].
  static dynamic parseHttpResponse(
    http.Response response, {
    String? defaultErrorMessage,
  }) {
    final statusCode = response.statusCode;

    // Check for success status codes (200 - 299)
    if (statusCode >= 200 && statusCode < 300) {
      if (response.body.isEmpty) return null;
      try {
        return jsonDecode(response.body);
      } catch (e) {
        // Body was not JSON (e.g. plain text or empty)
        return response.body;
      }
    }

    // Handle error status codes
    String? serverMessage;
    try {
      if (response.body.isNotEmpty) {
        final body = jsonDecode(response.body);
        if (body is Map) {
          serverMessage = body['message']?.toString() ??
              body['error']?.toString() ??
              body['msg']?.toString() ??
              body['detail']?.toString();
        }
      }
    } catch (_) {
      // Non-JSON response (e.g., 502 Bad Gateway HTML page)
      serverMessage = null;
    }

    final cleanMessage = (serverMessage != null && !_containsTechnicalLeakage(serverMessage))
        ? sanitizeMessage(serverMessage)
        : defaultErrorMessage;

    if (statusCode == 401) {
      throw UnauthorizedException(
        message: cleanMessage ?? 'Your session has expired. Please log in again.',
        technicalDetails: response.body,
      );
    }

    if (statusCode == 403) {
      throw ForbiddenException(
        message: cleanMessage ?? 'You do not have permission to perform this action.',
        technicalDetails: response.body,
      );
    }

    if (statusCode == 404) {
      throw NotFoundException(
        message: cleanMessage ?? 'Requested item was not found.',
        technicalDetails: response.body,
      );
    }

    if (statusCode == 400 || statusCode == 422) {
      throw ValidationException(
        cleanMessage ?? 'Invalid request. Please verify the entered data.',
        statusCode: statusCode,
        technicalDetails: response.body,
      );
    }

    if (statusCode >= 500) {
      throw ServerAppException(
        statusCode: statusCode,
        message: 'Server is temporarily unavailable. Please try again later.',
        technicalDetails: response.body,
      );
    }

    throw ServerAppException(
      statusCode: statusCode,
      message: cleanMessage ?? 'An unexpected error occurred. Please try again.',
      technicalDetails: response.body,
    );
  }

  /// Removes URLs, IPs, query params, and HTML tags from any user-facing message.
  static String sanitizeMessage(String input) {
    var sanitized = input;

    // Remove URLs (http://, https://)
    sanitized = sanitized.replaceAll(
      RegExp(r'https?://[^\s<>"]+|www\.[^\s<>"]+'),
      '',
    );

    // Remove HTML tags
    sanitized = sanitized.replaceAll(RegExp(r'<[^>]*>'), '');

    // Remove multiple consecutive spaces/newlines
    sanitized = sanitized.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (sanitized.isEmpty) {
      return 'An unexpected error occurred. Please try again.';
    }

    return sanitized;
  }

  /// Detects whether a string contains technical jargon, URLs, or database leakages.
  static bool _containsTechnicalLeakage(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('http://') ||
        lower.contains('https://') ||
        lower.contains('api/v1') ||
        lower.contains('exception') ||
        lower.contains('sql') ||
        lower.contains('postgres') ||
        lower.contains('mongo') ||
        lower.contains('database') ||
        lower.contains('stack trace') ||
        lower.contains('syntax error') ||
        lower.contains('<!doctype') ||
        lower.contains('<html') ||
        lower.contains('clientexception') ||
        lower.contains('socketexception') ||
        lower.contains('os error') ||
        lower.contains('failed host lookup') ||
        lower.contains('errno =')) {
      return true;
    }
    return false;
  }
}
