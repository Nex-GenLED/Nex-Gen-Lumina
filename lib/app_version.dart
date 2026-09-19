/// Single source of truth for the app version shown in-app and stamped onto
/// telemetry.
///
/// MUST BE BUMPED WITH `pubspec.yaml` ON EVERY RELEASE.
///
/// There is deliberately no runtime source for this. The project does not
/// depend on `package_info_plus`, and adding a plugin (with its native config)
/// to a release candidate was judged a bigger risk than a one-line constant —
/// see the note this comment was lifted from in
/// `features/installer/staff_auth_telemetry.dart`. That trade-off is only
/// safe if there is exactly ONE literal to bump, which is why this file
/// exists: the login screen and the installer telemetry stamp had drifted to
/// `v2.2.0` and `2.5.10+97` respectively, three minor versions apart, and a
/// stale value defeats the whole point of the S-5 adoption metric (telling
/// ADOPTED builds from STALE ones).
///
/// Logged as debt in docs/BUGS_AND_DEBT.md.
library;

/// Full version string, matching `version:` in `pubspec.yaml` exactly,
/// including the `+buildNumber` suffix.
const String kAppVersion = '2.5.10+101';

/// Marketing version only — the part before `+`, e.g. `2.5.10`.
///
/// This is what user-facing surfaces should show; the build number is an
/// internal artifact identifier and means nothing to a customer.
String get kAppVersionName => kAppVersion.split('+').first;
