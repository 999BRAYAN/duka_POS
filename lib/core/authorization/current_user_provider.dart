import 'package:duka_pos/core/database/database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The signed-in [User] for this session, or null when signed out.
///
/// Held in memory only: closing the tab or reloading signs you out. That is
/// deliberate for a till that sits on a shop counter — an unattended browser
/// should not stay signed in as the manager — and it avoids putting a
/// session token in browser storage where any script on the page could read
/// it.
final currentUserProvider = StateProvider<User?>((ref) => null);
