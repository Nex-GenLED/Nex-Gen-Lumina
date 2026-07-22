/// How a controller is reachable on the local network.
///
/// Persisted on each `/users/{uid}/controllers/{cid}` doc as the
/// `connectionMethod` field. Stable string keys are produced/consumed by
/// [connectionMethodToJson] / [connectionMethodFromJson] so the Firestore
/// representation does not depend on Dart enum ordering.
enum ConnectionMethod {
  /// Wired only. WiFi credentials have been cleared on the controller.
  ethernet,

  /// Wireless only. No Ethernet interface present (or unplugged).
  wifi,

  /// Both interfaces are reporting as active. Legacy state or a transient
  /// during a switch — the installer flow treats this as "needs resolution"
  /// because the controller has two IPs / two router entries.
  ethernetWifiActive,

  /// State not yet known. Used when a controller is added before its
  /// `/json/info` has been inspected (e.g. fresh BLE-provisioned units).
  unknown,
}

const _ethernet = 'ethernet';
const _wifi = 'wifi';
const _ethernetWifiActive = 'ethernet_wifi_active';
const _unknown = 'unknown';

/// Serialises a [ConnectionMethod] to its stable Firestore string key.
String connectionMethodToJson(ConnectionMethod method) {
  switch (method) {
    case ConnectionMethod.ethernet:
      return _ethernet;
    case ConnectionMethod.wifi:
      return _wifi;
    case ConnectionMethod.ethernetWifiActive:
      return _ethernetWifiActive;
    case ConnectionMethod.unknown:
      return _unknown;
  }
}

/// Parses a Firestore string into a [ConnectionMethod], or `null` if the
/// value is missing or unrecognised. Callers decide whether to treat
/// `null` as [ConnectionMethod.unknown] or as "no value persisted yet".
ConnectionMethod? connectionMethodFromJson(Object? value) {
  if (value is! String) return null;
  switch (value) {
    case _ethernet:
      return ConnectionMethod.ethernet;
    case _wifi:
      return ConnectionMethod.wifi;
    case _ethernetWifiActive:
      return ConnectionMethod.ethernetWifiActive;
    case _unknown:
      return ConnectionMethod.unknown;
  }
  return null;
}
