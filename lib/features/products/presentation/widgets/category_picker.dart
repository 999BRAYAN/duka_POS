import 'package:duka_pos/core/authorization/authorization_exceptions.dart';
import 'package:duka_pos/core/authorization/permission.dart';
import 'package:duka_pos/core/authorization/providers.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/products/data/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Picks a category, and can create one without leaving the form.
///
/// Categories only exist to group products, so sending someone to a separate
/// screen to make one mid-way through adding a product would be a detour
/// with nothing else on it.
class CategoryPicker extends ConsumerWidget {
  const CategoryPicker({
    required this.categories,
    required this.selectedId,
    required this.onChanged,
    super.key,
  });

  final List<Category> categories;
  final int? selectedId;
  final ValueChanged<int?> onChanged;

  static const _newCategory = -1;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A selected category that has since been deleted would otherwise assert
    // inside DropdownButton.
    final valueExists = categories.any((c) => c.id == selectedId);

    return DropdownButtonFormField<int?>(
      initialValue: valueExists ? selectedId : null,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Category'),
      items: [
        const DropdownMenuItem<int?>(value: null, child: Text('No category')),
        for (final category in categories)
          DropdownMenuItem<int?>(value: category.id, child: Text(category.name)),
        const DropdownMenuItem<int?>(
          value: _newCategory,
          child: Text('New category…'),
        ),
      ],
      onChanged: (value) async {
        if (value != _newCategory) {
          onChanged(value);
          return;
        }
        final created = await _createCategory(context, ref);
        if (created != null) onChanged(created.id);
      },
    );
  }

  Future<Category?> _createCategory(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New category'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (value) {
            FocusManager.instance.primaryFocus?.unfocus();
            Navigator.of(context).pop(value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              // See product_form_screen.dart's _submit for why this unfocus
              // matters — this field still holds focus when the button is
              // clicked with a mouse.
              FocusManager.instance.primaryFocus?.unfocus();
              Navigator.of(context).pop(controller.text.trim());
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (name == null || name.isEmpty || !context.mounted) return null;

    final messenger = ScaffoldMessenger.of(context);
    try {
      // Categories are part of the catalog, so they answer to the same
      // permission products do.
      ref.read(authorizationServiceProvider).require(Permission.manageProducts);
      return await ref.read(categoryRepositoryProvider).addCategory(name: name);
    } on UnauthorizedException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
      return null;
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not add the category: $e')));
      return null;
    }
  }
}
