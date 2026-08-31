import 'package:duka_pos/core/database/database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The signed-in [User] for this session, or null when signed out. The auth
/// flow (see UserRepository.authenticate/hasManager) doesn't call into this
/// yet — until it does, every permission check sees no user signed in.
final currentUserProvider = StateProvider<User?>((ref) => null);
