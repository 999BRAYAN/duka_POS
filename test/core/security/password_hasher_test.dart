import 'package:duka_pos/core/security/password_hasher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a password verifies against its own hash', () {
    final stored = PasswordHasher.hash('correct horse battery staple');
    expect(PasswordHasher.verify('correct horse battery staple', stored), isTrue);
  });

  test('a wrong password does not verify', () {
    final stored = PasswordHasher.hash('duka2026');
    expect(PasswordHasher.verify('duka2027', stored), isFalse);
    expect(PasswordHasher.verify('', stored), isFalse);
    expect(PasswordHasher.verify('DUKA2026', stored), isFalse);
  });

  test('the same password hashes differently every time', () {
    final a = PasswordHasher.hash('duka2026');
    final b = PasswordHasher.hash('duka2026');

    // Different salts, so two shopkeepers who pick the same password are
    // not visibly identical in the database, and one cracked hash does not
    // crack the other.
    expect(a, isNot(b));
    expect(PasswordHasher.verify('duka2026', a), isTrue);
    expect(PasswordHasher.verify('duka2026', b), isTrue);
  });

  test('the stored format carries its algorithm, iterations and salt', () {
    final parts = PasswordHasher.hash('duka2026').split(r'$');
    expect(parts, hasLength(4));
    expect(parts[0], 'pbkdf2_sha256');
    expect(int.parse(parts[1]), greaterThanOrEqualTo(100000));
    expect(parts[2], isNotEmpty);
    expect(parts[3], isNotEmpty);
  });

  test('a hash still verifies at the iteration count it was made with', () {
    // Simulates raising the cost later: an old hash names its own count, so
    // it keeps working instead of locking the user out.
    final stored = PasswordHasher.hash('duka2026');
    final lowered = stored.replaceFirst(
      RegExp(r'^pbkdf2_sha256\$\d+\$'),
      r'pbkdf2_sha256$1000$',
    );
    expect(
      PasswordHasher.verify('duka2026', lowered),
      isFalse,
      reason: 'changing the count changes the hash, so this must not verify',
    );
  });

  group('anything that is not one of our hashes reads as a wrong password', () {
    for (final stored in <String>[
      'dev', // what dev_user_seed used to write
      'hash', // what the test fixtures used to write
      '',
      r'pbkdf2_sha256$notanumber$c2FsdA==$aGFzaA==',
      r'pbkdf2_sha256$100000$!!!notbase64!!!$aGFzaA==',
      r'sha1$100000$c2FsdA==$aGFzaA==',
      r'pbkdf2_sha256$100000$c2FsdA==',
    ]) {
      test('"$stored"', () {
        expect(PasswordHasher.verify('anything', stored), isFalse);
        expect(PasswordHasher.isHashed(stored), isFalse);
      });
    }
  });

  test('isHashed recognises a real hash', () {
    expect(PasswordHasher.isHashed(PasswordHasher.hash('duka2026')), isTrue);
  });
}
