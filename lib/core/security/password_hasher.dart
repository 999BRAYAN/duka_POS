import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Hashes and verifies passwords with PBKDF2-HMAC-SHA256.
///
/// PBKDF2 rather than a bare SHA-256 digest because a digest is designed to
/// be fast, which is exactly wrong for passwords: an attacker holding the
/// database can try billions of guesses a second against one. PBKDF2 makes
/// each guess cost [_iterations] hashes instead of one.
///
/// PBKDF2 rather than bcrypt/argon2 because it is implementable on top of
/// `package:crypto`, which is pure Dart and runs on Flutter web. The
/// stronger algorithms available on pub for Dart come with native
/// components that this project's web target cannot load.
///
/// The stored string carries everything needed to verify it later, so no
/// schema change and no second column:
///
///     pbkdf2_sha256$<iterations>$<base64 salt>$<base64 hash>
///
/// The iteration count travels with each hash, so it can be raised later
/// without invalidating existing passwords — old hashes keep verifying at
/// the count they were made with.
abstract final class PasswordHasher {
  static const _algorithm = 'pbkdf2_sha256';

  /// Deliberately modest. This runs in the browser on low-end hardware at a
  /// shop counter, and a cashier signing in should not wait seconds for it.
  /// It is worth roughly a hundred thousand times a bare digest, which is
  /// the difference that matters.
  static const _iterations = 100000;

  static const _saltBytes = 16;
  static const _keyBytes = 32;

  static final _random = Random.secure();

  /// Hashes [password] with a fresh random salt.
  static String hash(String password) {
    final salt = Uint8List.fromList(
      List<int>.generate(_saltBytes, (_) => _random.nextInt(256)),
    );
    final key = _pbkdf2(password, salt, _iterations, _keyBytes);
    return '$_algorithm\$$_iterations\$${base64.encode(salt)}\$${base64.encode(key)}';
  }

  /// Whether [password] produced [stored].
  ///
  /// Returns false for anything unparseable rather than throwing: rows
  /// written before this class existed hold plain strings, and they must
  /// read as "wrong password", never as a crash on the login screen.
  static bool verify(String password, String stored) {
    final decoded = _decode(stored);
    if (decoded == null) return false;

    final actual = _pbkdf2(
      password,
      decoded.salt,
      decoded.iterations,
      decoded.key.length,
    );
    return _constantTimeEquals(actual, decoded.key);
  }

  /// Whether [stored] is a well-formed hash this class produced, as opposed
  /// to a plain string left over from before real hashing existed — or a
  /// corrupted one, which is no more usable than a plaintext value and is
  /// reported the same way.
  static bool isHashed(String stored) => _decode(stored) != null;

  /// The parsed pieces of [stored], or null if it is not a usable hash.
  static ({int iterations, Uint8List salt, Uint8List key})? _decode(String stored) {
    final parts = stored.split(r'$');
    if (parts.length != 4 || parts[0] != _algorithm) return null;

    final iterations = int.tryParse(parts[1]);
    if (iterations == null || iterations <= 0) return null;

    try {
      return (
        iterations: iterations,
        salt: base64.decode(parts[2]),
        key: base64.decode(parts[3]),
      );
    } on FormatException {
      return null;
    }
  }

  static Uint8List _pbkdf2(
    String password,
    Uint8List salt,
    int iterations,
    int keyLength,
  ) {
    final hmac = Hmac(sha256, utf8.encode(password));
    final blockCount = (keyLength / 32).ceil();
    final output = BytesBuilder();

    for (var block = 1; block <= blockCount; block++) {
      // U1 = HMAC(password, salt || INT_32_BE(block))
      final blockIndex = Uint8List(4)
        ..[0] = block >> 24
        ..[1] = block >> 16
        ..[2] = block >> 8
        ..[3] = block;

      var u = Uint8List.fromList(
        hmac.convert(<int>[...salt, ...blockIndex]).bytes,
      );
      final accumulated = Uint8List.fromList(u);

      // Un = HMAC(password, Un-1), XORed into the running result.
      for (var i = 1; i < iterations; i++) {
        u = Uint8List.fromList(hmac.convert(u).bytes);
        for (var j = 0; j < accumulated.length; j++) {
          accumulated[j] ^= u[j];
        }
      }
      output.add(accumulated);
    }

    return Uint8List.fromList(output.takeBytes().sublist(0, keyLength));
  }

  /// Compares without leaking, through timing, how many leading bytes
  /// matched — the whole comparison costs the same whatever the input.
  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }
}
