import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ionet/core/providers/auth_provider.dart';
import 'package:ionet/core/providers/device_provider.dart';
import 'package:ionet/core/providers/support_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AuthProvider Offline Session & Persistence Tests', () {
    test('tryRestoreSession restores cached profile and remains authenticated offline', () async {
      SharedPreferences.setMockInitialValues({
        'jwt_token': 'mock_jwt_token_xyz',
        'user_id': 'user_123',
        'user_email': 'test@example.com',
        'user_name': 'Test Engineer',
        'user_mobile': '9876543210',
        'user_credits': 150,
        'is_first_time_user': false,
      });

      final authProvider = AuthProvider();

      // In unit test without backend, fetchProfile will throw network error.
      // tryRestoreSession should catch it, retain authentication, and NOT wipe token!
      final restored = await authProvider.tryRestoreSession();

      expect(restored, isTrue);
      expect(authProvider.isAuthenticated, isTrue);
      expect(authProvider.token, equals('mock_jwt_token_xyz'));
      expect(authProvider.userId, equals('user_123'));
      expect(authProvider.email, equals('test@example.com'));
      expect(authProvider.name, equals('Test Engineer'));
      expect(authProvider.mobile, equals('9876543210'));
      expect(authProvider.credits, equals(150));
      expect(authProvider.isFirstTimeUser, isFalse);

      // Verify token was NOT deleted from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('jwt_token'), equals('mock_jwt_token_xyz'));
    });

    test('tryRestoreSession returns false if no token is saved', () async {
      SharedPreferences.setMockInitialValues({});
      final authProvider = AuthProvider();
      final restored = await authProvider.tryRestoreSession();

      expect(restored, isFalse);
      expect(authProvider.isAuthenticated, isFalse);
    });

    test('logout clears all locally stored profile credentials and token', () async {
      SharedPreferences.setMockInitialValues({
        'jwt_token': 'mock_jwt_token_xyz',
        'user_id': 'user_123',
        'user_email': 'test@example.com',
        'user_name': 'Test Engineer',
        'user_credits': 100,
        'is_first_time_user': false,
      });

      final authProvider = AuthProvider();
      await authProvider.tryRestoreSession();
      expect(authProvider.isAuthenticated, isTrue);

      await authProvider.logout();

      expect(authProvider.isAuthenticated, isFalse);
      expect(authProvider.token, isNull);
      expect(authProvider.name, isNull);
      expect(authProvider.email, isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('jwt_token'), isNull);
      expect(prefs.getString('user_id'), isNull);
      expect(prefs.getString('user_name'), isNull);
      expect(prefs.getString('user_email'), isNull);
      expect(prefs.getInt('user_credits'), isNull);
    });
  });

  group('DeviceProvider Local Caching & Lifecycle Tests', () {
    test('loadCachedDevices restores devices from SharedPreferences', () async {
      final mockDevicesJson = [
        {
          'deviceId': 'DEV-001',
          'deviceName': 'Power Inverter 1',
          'accessType': 'OWNER',
          'lastMessage': 'Operational',
          'updatedAt': '2026-09-09T10:00:00Z',
        },
        {
          'deviceId': 'DEV-002',
          'deviceName': 'Solar Monitor 2',
          'accessType': 'GUEST',
          'lastMessage': 'Standby',
          'updatedAt': '2026-09-09T10:00:00Z',
        },
      ];

      SharedPreferences.setMockInitialValues({
        'cached_devices': jsonEncode(mockDevicesJson),
      });

      final deviceProvider = DeviceProvider();
      expect(deviceProvider.devices, isEmpty);

      await deviceProvider.loadCachedDevices();

      expect(deviceProvider.devices.length, equals(2));
      expect(deviceProvider.devices[0].id, equals('DEV-001'));
      expect(deviceProvider.devices[0].name, equals('Power Inverter 1'));
      expect(deviceProvider.devices[0].isOwner, isTrue);
      expect(deviceProvider.devices[1].id, equals('DEV-002'));
      expect(deviceProvider.devices[1].name, equals('Solar Monitor 2'));
      expect(deviceProvider.devices[1].isOwner, isFalse);
    });

    test('DeviceProvider clearSession resets internal state and removes cached devices', () async {
      SharedPreferences.setMockInitialValues({
        'cached_devices': jsonEncode([
          {'deviceId': 'DEV-001', 'deviceName': 'Device 1'}
        ]),
      });

      final deviceProvider = DeviceProvider();
      await deviceProvider.loadCachedDevices();
      expect(deviceProvider.devices, isNotEmpty);

      // Call clearSession
      await deviceProvider.clearSession();

      expect(deviceProvider.devices, isEmpty);
      expect(deviceProvider.isLoading, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cached_devices'), isNull);
    });

    test('SupportProvider clearSession clears channels and subscriptions', () {
      final supportProvider = SupportProvider();

      supportProvider.clearSession();

      expect(supportProvider.channels, isEmpty);
      expect(supportProvider.subscribedChannels, isEmpty);
      expect(supportProvider.isLoading, isFalse);
      expect(supportProvider.error, isNull);
    });
  });
}
