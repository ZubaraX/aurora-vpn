import '../../data/models/enums.dart';
import '../../data/models/vpn_settings.dart';

class TriggerSwitch {
  const TriggerSwitch({
    required this.appId,
    required this.networkType,
    required this.profileIds,
    this.disconnect = false,
  });

  final String appId;
  final String networkType;
  final List<String> profileIds;

  /// The trigger is set to "no VPN" for this network: tear the tunnel down
  /// instead of connecting.
  final bool disconnect;

  String get profileId => profileIds.isEmpty ? '' : profileIds.first;
}

/// Stateful decision logic for application-triggered server changes.
///
/// The native inventory reports foreground package ids. This class performs
/// edge detection, remembers the active trigger session, and emits a switch
/// only when an application opens or its physical network changes.
class TriggerAppMonitor {
  Set<String> _previousActive = {};
  String? _sessionApp;
  String? _sessionNetwork;
  List<String>? _sessionProfiles;

  TriggerSwitch? evaluate({
    required VpnSettings settings,
    required Set<String> runningIds,
    required String networkType,
    required ConnectionStatus connectionStatus,
    required String? activeNodeId,
  }) {
    final triggers = settings.triggerApps;
    if (triggers.isEmpty) {
      reset();
      return null;
    }

    final triggerByLower = {
      for (final id in triggers.keys) id.toLowerCase(): id,
    };
    final active = runningIds
        .map((id) => triggerByLower[id.toLowerCase()])
        .whereType<String>()
        .toSet();
    final newlyActive = active.difference(_previousActive);
    _previousActive = active;

    if (newlyActive.isNotEmpty) {
      final appId = newlyActive.last;
      final resolved = settings.triggerProfilesFor(appId, networkType);
      _sessionApp = appId;
      _sessionNetwork = networkType;
      _sessionProfiles = resolved;
      return _switchFor(appId, networkType, resolved, connectionStatus, activeNodeId);
    }

    final appId = _sessionApp;
    if (appId == null || !active.contains(appId)) {
      _sessionApp = null;
      _sessionNetwork = null;
      _sessionProfiles = null;
      return null;
    }

    if (networkType == _sessionNetwork) return null;

    final resolved = settings.triggerProfilesFor(appId, networkType);
    _sessionNetwork = networkType;
    if (_sameProfiles(resolved, _sessionProfiles)) return null;

    _sessionProfiles = resolved;
    return _switchFor(appId, networkType, resolved, connectionStatus, activeNodeId);
  }

  /// Builds the switch for a resolved selection, honouring the "no VPN"
  /// sentinel (tear down instead of connect).
  static TriggerSwitch? _switchFor(
    String appId,
    String networkType,
    List<String> resolved,
    ConnectionStatus connectionStatus,
    String? activeNodeId,
  ) {
    final noVpn = resolved.length == 1 && resolved.first == kTriggerNoVpn;
    if (noVpn) {
      // Only act if the tunnel is currently up — otherwise there is nothing to
      // turn off.
      if (!connectionStatus.isActive) return null;
      return TriggerSwitch(
        appId: appId,
        networkType: networkType,
        profileIds: const [],
        disconnect: true,
      );
    }
    return _needsSwitch(connectionStatus, activeNodeId, resolved)
        ? TriggerSwitch(
            appId: appId,
            networkType: networkType,
            profileIds: resolved,
          )
        : null;
  }

  void reset() {
    _previousActive = {};
    _sessionApp = null;
    _sessionNetwork = null;
    _sessionProfiles = null;
  }

  static bool _needsSwitch(
    ConnectionStatus connectionStatus,
    String? activeNodeId,
    List<String> profileIds,
  ) {
    if (!connectionStatus.isActive) return true;
    if (profileIds.isEmpty) return false;
    return !profileIds.contains(activeNodeId);
  }

  static bool _sameProfiles(List<String> a, List<String>? b) {
    if (b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
