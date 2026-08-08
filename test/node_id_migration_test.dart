import 'package:aurora/data/local/node_id_migration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('remaps every node-id-bearing settings field via the id map', () {
    final idMap = {
      'oldA': 'newA',
      'oldB': 'newB',
      'oldC': 'newC',
    };
    final settings = {
      'activeNodeId': 'oldA',
      'triggerApps': {'app1': 'oldA', 'app2': ''},
      'triggerWifiProfiles': {'app1': 'oldB'},
      'triggerMobileProfiles': {
        'app1': ['oldA', 'oldC'],
      },
      'domainZoneRules': {'ru': 'oldB', 'com': 'direct'},
      'tunMode': true,
    };

    final out = NodeIdMigration.remapSettings(settings, idMap);

    expect(out['activeNodeId'], 'newA');
    expect(out['triggerApps'], {'app1': 'newA', 'app2': ''});
    expect(out['triggerWifiProfiles'], {'app1': 'newB'});
    expect(out['triggerMobileProfiles'], {
      'app1': ['newA', 'newC'],
    });
    // Non-node targets pass through untouched.
    expect(out['domainZoneRules'], {'ru': 'newB', 'com': 'direct'});
    // Unknown ids and unrelated fields are preserved.
    expect(out['tunMode'], true);
  });

  test('ids not in the map (already migrated) are left unchanged', () {
    final out = NodeIdMigration.remapSettings(
      {'activeNodeId': 'unknown', 'domainZoneRules': {'ru': 'proxy'}},
      {'oldA': 'newA'},
    );
    expect(out['activeNodeId'], 'unknown');
    expect(out['domainZoneRules'], {'ru': 'proxy'});
  });
}
