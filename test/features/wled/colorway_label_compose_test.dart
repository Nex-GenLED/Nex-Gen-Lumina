import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/colorway_effect_selector.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';

LibraryNode _palette(String name, {String? parentId = 'arch_k3500'}) =>
    LibraryNode(
      id: 'arch_k3500_1on2off',
      name: name,
      nodeType: LibraryNodeType.palette,
      parentId: parentId,
    );

LibraryNode _folder({required String name, String? description}) =>
    LibraryNode(
      id: 'arch_k3500',
      name: name,
      description: description,
      nodeType: LibraryNodeType.folder,
      parentId: 'cat_arch',
    );

void main() {
  group('composeColorwayLabel', () {
    test('parent with name + description → "<name> <desc>, <leaf>"', () {
      final palette = _palette('1 On 2 Off');
      final parent = _folder(name: '3500K', description: 'Soft White');
      expect(
        composeColorwayLabel(palette, parent),
        '3500K Soft White, 1 On 2 Off',
      );
    });

    test('parent with name + null description → "<name>, <leaf>"', () {
      final palette = _palette('1 On 2 Off');
      final parent = _folder(name: '3500K', description: null);
      expect(
        composeColorwayLabel(palette, parent),
        '3500K, 1 On 2 Off',
      );
    });

    test('parent with name + empty description → "<name>, <leaf>"', () {
      final palette = _palette('1 On 2 Off');
      final parent = _folder(name: '3500K', description: '');
      expect(
        composeColorwayLabel(palette, parent),
        '3500K, 1 On 2 Off',
      );
    });

    test('null parent → bare leaf name', () {
      final palette = _palette('1 On 2 Off', parentId: null);
      expect(composeColorwayLabel(palette, null), '1 On 2 Off');
    });

    test('parent with empty name → bare leaf name (treat parent as missing)',
        () {
      final palette = _palette('1 On 2 Off');
      final parent = _folder(name: '', description: 'Soft White');
      expect(composeColorwayLabel(palette, parent), '1 On 2 Off');
    });
  });
}
