import 'package:duka_pos/core/authorization/authorization_exceptions.dart';
import 'package:duka_pos/core/authorization/authorization_service.dart';
import 'package:duka_pos/core/authorization/permission.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:flutter_test/flutter_test.dart';

User _userWithRole(String role) {
  return User(
    id: 1,
    uuid: 'u1',
    username: 'jdoe',
    passwordHash: 'hash',
    fullName: 'Jane Doe',
    role: role,
    isActive: true,
    createdAt: DateTime(2026),
  );
}

void main() {
  test('admin and manager can manageProducts', () {
    expect(
      AuthorizationService(_userWithRole('admin')).can(Permission.manageProducts),
      isTrue,
    );
    expect(
      AuthorizationService(_userWithRole('manager')).can(Permission.manageProducts),
      isTrue,
    );
  });

  test('cashier cannot manageProducts', () {
    expect(
      AuthorizationService(_userWithRole('cashier')).can(Permission.manageProducts),
      isFalse,
    );
  });

  test('no signed-in user cannot manageProducts', () {
    expect(AuthorizationService(null).can(Permission.manageProducts), isFalse);
  });

  test('require throws UnauthorizedException when not permitted', () {
    expect(
      () => AuthorizationService(_userWithRole('cashier')).require(Permission.manageProducts),
      throwsA(isA<UnauthorizedException>()),
    );
  });

  test('require does nothing when permitted', () {
    expect(
      () => AuthorizationService(_userWithRole('manager')).require(Permission.manageProducts),
      returnsNormally,
    );
  });

  test('admin and manager can receiveStock; cashier cannot', () {
    expect(
      AuthorizationService(_userWithRole('admin')).can(Permission.receiveStock),
      isTrue,
    );
    expect(
      AuthorizationService(_userWithRole('manager')).can(Permission.receiveStock),
      isTrue,
    );
    expect(
      AuthorizationService(_userWithRole('cashier')).can(Permission.receiveStock),
      isFalse,
    );
  });

  test('every role can processSale, including cashier', () {
    for (final role in ['admin', 'manager', 'cashier']) {
      expect(
        AuthorizationService(_userWithRole(role)).can(Permission.processSale),
        isTrue,
        reason: '$role should be able to processSale',
      );
    }
  });
}
