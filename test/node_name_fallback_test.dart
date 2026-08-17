import 'package:aurora/data/models/enums.dart';
import 'package:aurora/data/models/proxy_node.dart';
import 'package:aurora/state/profile_controller.dart';
import 'package:flutter_test/flutter_test.dart';

ProxyNode node(String id, String name) => ProxyNode(
      id: id,
      name: name,
      protocol: ProxyProtocol.vless,
      server: 'a.com',
      port: 443,
    );

void main() {
  test('a saved id still resolves after the provider rotates credentials', () {
    // The server keeps its name but gets new credentials, so its content-derived
    // id changes. The saved selection must follow the name, not vanish.
    final state = ProfileState(
      nodes: [node('new-id', 'Germany')],
      nodeNames: const {'old-id': 'Germany'},
    );
    expect(state.nodeById('old-id')?.id, 'new-id');
  });

  test('exact id match still wins over the name fallback', () {
    final state = ProfileState(
      nodes: [node('a', 'Germany'), node('b', 'Germany')],
      nodeNames: const {'b': 'Germany'},
    );
    expect(state.nodeById('b')?.id, 'b');
  });

  test('an unknown id with no remembered name stays unresolved', () {
    final state = ProfileState(nodes: [node('a', 'Germany')]);
    expect(state.nodeById('gone'), isNull);
    expect(state.nodeById(null), isNull);
  });
}
