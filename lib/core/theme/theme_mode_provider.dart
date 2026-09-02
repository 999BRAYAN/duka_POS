import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Light, dark, or whatever the device is set to.
///
/// Kept in memory: the whole app is one browser profile and there is no
/// settings table yet, so this resets on reload rather than pretending to be
/// a stored preference. [ThemeMode.system] is the default, so a till in a
/// dark shop follows the machine without anyone choosing.
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
