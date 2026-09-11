import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ionet/core/errors/app_exceptions.dart';
import 'package:ionet/core/errors/error_handler.dart';

void main() {
  group('ErrorHandler & AppException Sanitization Tests', () {
    test('SocketException maps to NetworkException without leaking host or IP', () {
      const socketError = SocketException(
        "Failed host lookup: 'api.ionet.co.in' (OS Error: No address associated with hostname, errno = 7)",
        osError: OSError('No address associated with hostname', 7),
        address: null,
        port: 443,
      );

      final result = ErrorHandler.handle(socketError);

      expect(result, isA<NetworkException>());
      expect(result.userMessage, 'No internet connection. Please check your network and try again.');
      expect(result.userMessage.contains('api.ionet.co.in'), isFalse);
      expect(result.userMessage.contains('errno'), isFalse);
      expect(result.userMessage.contains('443'), isFalse);
    });

    test('ClientException with host lookup failure maps to NetworkException', () {
      final clientError = http.ClientException(
        "Failed host lookup: 'api.ionet.co.in' (OS Error: No address associated with hostname, errno = 7)",
        Uri.parse('https://api.ionet.co.in/api/v1/auth/request-otp'),
      );

      final result = ErrorHandler.handle(clientError);

      expect(result, isA<NetworkException>());
      expect(result.userMessage, 'No internet connection. Please check your network and try again.');
      expect(result.userMessage.contains('https://'), isFalse);
      expect(result.userMessage.contains('request-otp'), isFalse);
    });

    test('TimeoutException maps to TimeoutAppException', () {
      final timeoutError = TimeoutException('Connection timed out after 15s');

      final result = ErrorHandler.handle(timeoutError);

      expect(result, isA<TimeoutAppException>());
      expect(result.userMessage, 'The connection timed out. Please try again.');
    });

    test('FormatException from HTML 502 Bad Gateway maps to ServerAppException', () {
      const formatError = FormatException("Unexpected character '<' at character 1");

      final result = ErrorHandler.handle(formatError);

      expect(result, isA<ServerAppException>());
      expect(result.userMessage.contains('<'), isFalse);
      expect(result.userMessage, 'Received an invalid response format from server.');
    });

    test('Raw error containing SQL or database trace is sanitized', () {
      final rawError = Exception(
        'database query failed: SELECT * FROM devices WHERE id = 123 at postgresql://user:pass@10.0.0.1:5432/ionet',
      );

      final result = ErrorHandler.handle(rawError);

      expect(result, isA<ServerAppException>());
      expect(result.userMessage, 'Something went wrong. Please try again later.');
      expect(result.userMessage.contains('postgres'), isFalse);
      expect(result.userMessage.contains('10.0.0.1'), isFalse);
      expect(result.userMessage.contains('SELECT'), isFalse);
    });

    test('User-safe backend message is preserved in ValidationException', () {
      final safeError = Exception('Device ID must be exactly 12 characters');

      final result = ErrorHandler.handle(safeError);

      expect(result, isA<ValidationException>());
      expect(result.userMessage, 'Device ID must be exactly 12 characters');
    });

    test('Sanitizer strips URLs and HTML tags from arbitrary messages', () {
      const dirtyMessage = '<p>Please check <b>https://api.ionet.co.in/docs</b> for help.</p>';

      final sanitized = ErrorHandler.sanitizeMessage(dirtyMessage);

      expect(sanitized.contains('<p>'), isFalse);
      expect(sanitized.contains('<b>'), isFalse);
      expect(sanitized.contains('https://'), isFalse);
      expect(sanitized, 'Please check for help.');
    });

    group('HTTP Response Status Code Parsing', () {
      test('200 OK with JSON returns decoded map', () {
        final response = http.Response('{"success": true, "data": {"id": "123"}}', 200);

        final result = ErrorHandler.parseHttpResponse(response);

        expect(result, isA<Map>());
        expect(result['success'], isTrue);
      });

      test('401 Unauthorized throws UnauthorizedException', () {
        final response = http.Response('{"message": "Token expired"}', 401);

        expect(
          () => ErrorHandler.parseHttpResponse(response),
          throwsA(isA<UnauthorizedException>()),
        );
      });

      test('403 Forbidden throws ForbiddenException', () {
        final response = http.Response('{"message": "Action not allowed"}', 403);

        expect(
          () => ErrorHandler.parseHttpResponse(response),
          throwsA(isA<ForbiddenException>()),
        );
      });

      test('404 Not Found throws NotFoundException', () {
        final response = http.Response('{"message": "Device not found"}', 404);

        expect(
          () => ErrorHandler.parseHttpResponse(response),
          throwsA(isA<NotFoundException>()),
        );
      });

      test('500 Internal Server Error with HTML body throws safe ServerAppException', () {
        final response = http.Response(
          '<html><body><h1>500 Internal Server Error</h1><p>Nginx/1.18.0</p></body></html>',
          500,
        );

        expect(
          () => ErrorHandler.parseHttpResponse(response),
          throwsA(predicate<ServerAppException>((e) {
            return !e.userMessage.contains('<html>') &&
                   !e.userMessage.contains('Nginx') &&
                   e.userMessage == 'Server is temporarily unavailable. Please try again later.';
          })),
        );
      });
    });
  });
}
