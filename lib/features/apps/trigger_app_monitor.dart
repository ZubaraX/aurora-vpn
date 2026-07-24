import '../../data/models/enums.dart';
import '../../data/models/vpn_settings.dart';

class TriggerSwitch {
  const TriggerSwitch({
    required this.appId,
    required this.networkType,
    required this.profileId,
  });

  final String appId;
  final String networkType;
  final String profileId;
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
  String? _sessionProfile;

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
      final profileId = settings.triggerProfileFor(appId, networkType);
      _sessionApp = appId;
      _sessionNetwork = networkType;
      _sessionProfile = profileId;
      return _needsSwitch(connectionStatus, activeNodeId, profileId)
          ? TriggerSwitch(
              appId: appId,
              networkType: networkType,
              profileId: profileId,
            )
          : null;
    }

    final appId = _sessionApp;
    if (appId == null || !active.contains(appId)) {
      _sessionApp = null;
      _sessionNetwork = null;
      _sessionProfile = null;
      return null;
    }

    if (networkType == _sessionNetwork) return null;

    final profileId = settings.triggerProfileFor(appId, networkType);
    _sessionNetwork = networkType;
    if (profileId == _sessionProfile) return null;

    _sessionProfile = profileId;
    return _needsSwitch(connectionStatus, activeNodeId, profileId)
        ? TriggerSwitch(
            appId: appId,
            networkType: networkType,
            profileId: profileId,
          )
        : null;
  }

  void reset() {
    _previousActive = {};
    _sessionApp = null;
    _sessionNetwork = null;
    _sessionProfile = null;
  }

  static bool _needsSwitch(
    ConnectionStatus connectionStatus,
    String? activeNodeId,
    String profileId,
  ) {
    if (!connectionStatus.isActive) return true;
    if (profileId.isEmpty) return false;
    return activeNodeId != profileId;
  }
}
