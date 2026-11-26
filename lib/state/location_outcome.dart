/// The result of asking for a location fix. A typed outcome instead of a
/// bool + string pair so every caller can offer the right recovery action
/// rather than a dead-end message.
enum LocationOutcome {
  /// A fresh fix is available.
  granted,

  /// The device's location toggle is off — no prompt can help.
  servicesOff,

  /// Permission was denied permanently; only system settings can fix it.
  blocked,

  /// The user said no to this prompt.
  denied,

  /// Permission looked fine but the fix failed (timeout, no signal).
  failed,
}

/// User-facing copy for an outcome. Kept with the type so the map, the
/// settings screen and the add flow cannot drift apart.
String locationMessage(LocationOutcome outcome) => switch (outcome) {
  LocationOutcome.granted => 'Location ready.',
  LocationOutcome.servicesOff => 'Location services are turned off.',
  LocationOutcome.blocked => 'Location is blocked for PhotoSpot.',
  LocationOutcome.denied => 'Location permission was denied.',
  LocationOutcome.failed => 'Could not get your location right now.',
};

/// Maps raw permission facts to an outcome. Pure so the decision is testable
/// without a device: services being off wins, because opening settings for a
/// blocked app while the toggle itself is off sends the user to the wrong page.
LocationOutcome classifyLocation({
  required bool servicesEnabled,
  required bool deniedForever,
  required bool denied,
}) {
  if (!servicesEnabled) return LocationOutcome.servicesOff;
  if (deniedForever) return LocationOutcome.blocked;
  if (denied) return LocationOutcome.denied;
  return LocationOutcome.granted;
}
