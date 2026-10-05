import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/controller_selection.dart';
import 'package:nexgen_command/features/site/controller_choice_prompt.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/services/bridge_pairing.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:nexgen_command/shared/write_result.dart';

/// Why an apply cannot be sent right now.
enum ApplyBlock {
  /// No controller is selected or registered.
  noController,

  /// #118 — two or more of the account's controllers answered and the
  /// customer has not said which one this phone uses.
  chooseController,

  /// #118 — this phone is pointed at an address that is none of this
  /// account's controllers (a selection left over from another account,
  /// or a record's old address). Nothing about remote access or a bridge
  /// is wrong, and saying so sent customers to the wrong screen.
  notThisAccount,

  /// The phone has no network at all.
  offline,

  /// The network check has not finished.
  connecting,

  /// Away from home, and this account has no Lumina Bridge to relay through.
  noBridge,

  /// Away from home, and nothing can relay to this controller.
  remoteNotSetUp,

  /// A channel source is still being read.
  channelsLoading,

  /// Away from home: no saved channel list, and the relay did not answer.
  homeNotAnswering,

  /// On the home network, and the controller's channels could not be read.
  controllerUnreadable,

  /// The customer's channel selection matches no channel on this controller.
  nothingSelected,

  /// Every channel that would be targeted is set to be left out.
  allLeftOut,
}

/// An [ApplyBlock] with the sentence to show for it.
class ApplyBlockedReason {
  final ApplyBlock kind;

  /// Customer-readable. No ids, addresses or status codes.
  final String message;

  const ApplyBlockedReason(this.kind, this.message);

  /// True when trying again shortly is likely to work without the customer
  /// changing anything.
  bool get isTransient =>
      kind == ApplyBlock.connecting || kind == ApplyBlock.channelsLoading;

  WriteResult toWriteResult() => WriteResult.blocked(message);

  @override
  String toString() => 'ApplyBlockedReason(${kind.name})';
}

/// Shown the moment an away-from-home apply is refused because the account
/// has no bridge (2026-09-30). Before this, the command was queued, nothing
/// picked it up, and 45 s later the customer read "check your connection".
const String kNoBridgeAwayMessage =
    "You're away from home. Control from anywhere requires a Lumina Bridge. "
    'Connect to your home Wi-Fi to control your lights.';

/// Null when an apply can be sent; otherwise the ONE reason it cannot.
///
/// WHY ONE PLACE. The gate being empty used to be handled by each caller on
/// its own: four returned silently, one said "Couldn't reach your lights" for
/// a command that was never sent, one said "check controller connection", and
/// one had a proper message. The customer's question is the same every time —
/// "why didn't my lights change?" — so the answer is decided here.
///
/// Checks run outermost first, so the reason names the first thing the
/// customer would have to fix.
final applyBlockedReasonProvider = Provider<ApplyBlockedReason?>((ref) {
  final remote = ref.watch(isRemoteModeProvider);

  if (ref.watch(wledRepositoryProvider) == null) {
    if (ref.watch(selectedDeviceIpProvider) == null) {
      if (ref.watch(controllerSelectionProvider).needsChoice) {
        return const ApplyBlockedReason(
          ApplyBlock.chooseController,
          'More than one of your controllers is on this network. Choose '
          'the one this phone should use in $kChooseControllerWhere.',
        );
      }
      return const ApplyBlockedReason(
        ApplyBlock.noController,
        'No controller is set up yet. Add your controller in Settings to '
        'control your lights.',
      );
    }
    final status = ref.watch(wledConnectivityStatusProvider).valueOrNull;
    if (status == ConnectivityStatus.offline) {
      return const ApplyBlockedReason(
        ApplyBlock.offline,
        'Your phone is offline. Connect to Wi-Fi or mobile data and try again.',
      );
    }
    // #118: an address that is none of this account's records. The relay
    // declined for want of a record id, not for want of a bridge or remote
    // access — say what is actually wrong.
    final records = ref.watch(controllersStreamProvider).valueOrNull;
    if (records != null &&
        records.isNotEmpty &&
        ref.watch(selectedControllerIdProvider) == null) {
      return const ApplyBlockedReason(
        ApplyBlock.notThisAccount,
        "This phone is set to a controller that isn't on your account. "
        'Choose your controller in $kChooseControllerWhere.',
      );
    }
    if (remote) {
      // The registry says no bridge is paired to this account, so the routed
      // repository declined to build a relay. Say so, in plain words. A
      // paired bridge that is merely offline never reaches this branch: the
      // relay is built for it and its failure reads "can't reach".
      if (ref.watch(pairedBridgeStateProvider) == PairedBridgeState.none) {
        return const ApplyBlockedReason(
          ApplyBlock.noBridge,
          kNoBridgeAwayMessage,
        );
      }
      return const ApplyBlockedReason(
        ApplyBlock.remoteNotSetUp,
        "You're away from home and remote access isn't set up for this "
        'controller. Connect to your home Wi-Fi, or set up Remote Access in '
        'Settings.',
      );
    }
    return const ApplyBlockedReason(
      ApplyBlock.connecting,
      'Still connecting to your lights. Try again in a moment.',
    );
  }

  if (ref.watch(effectiveChannelIdsProvider).isNotEmpty) return null;

  final census = ref.watch(applyChannelCensusProvider);
  if (census.ids.isEmpty) {
    if (census.pending) {
      return ApplyBlockedReason(
        ApplyBlock.channelsLoading,
        remote
            ? 'Still getting your channels from home. Try again in a moment.'
            : 'Still reading your controller. Try again in a moment.',
      );
    }
    return remote
        ? const ApplyBlockedReason(
            ApplyBlock.homeNotAnswering,
            "Couldn't reach your home from here, so your lights weren't "
            'changed. Check that your bridge and controller are powered on '
            'and online, then try again.',
          )
        : const ApplyBlockedReason(
            ApplyBlock.controllerUnreadable,
            "Couldn't read your controller's channels, so your lights "
            "weren't changed. Check that it's powered on and on this Wi-Fi "
            'network.',
          );
  }

  final selected = ref.watch(selectedChannelIdsProvider);
  if (selected != null && !census.ids.any(selected.contains)) {
    return const ApplyBlockedReason(
      ApplyBlock.nothingSelected,
      'No channels are selected. Choose a channel on the Home screen, or '
      'switch back to All Channels.',
    );
  }
  return const ApplyBlockedReason(
    ApplyBlock.allLeftOut,
    'The selected channels are all set to be left out. Include a channel on '
    'the Home screen to control it.',
  );
});

/// The customer-readable reason an apply cannot be sent, or null when it can.
///
/// Pass `ref.read` from a widget, a provider or a notifier:
///
/// ```dart
/// final channels = ref.read(effectiveChannelIdsProvider);
/// if (channels.isEmpty) {
///   showMessage(applyBlockedReason(ref.read) ?? kApplyBlockedFallback);
///   return;
/// }
/// ```
String? applyBlockedReason(
  T Function<T>(ProviderListenable<T> provider) read,
) =>
    read(applyBlockedReasonProvider)?.message;

/// For the caller that must show SOMETHING and found the gate closed with no
/// reason (it opened between the two reads).
const String kApplyBlockedFallback =
    "Your lights weren't changed. Try again in a moment.";
