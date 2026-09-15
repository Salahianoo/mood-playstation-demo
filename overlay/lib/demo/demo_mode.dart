/// Compiled with `--dart-define=DEMO_MODE=true` by build.sh. The seeder
/// double-checks it, so the overlay can never seed a non-demo build.
const bool kDemoMode = bool.fromEnvironment('DEMO_MODE');

/// Replaces the real owner password on the lock screens of the demo,
/// where it is shown to visitors in plain sight.
const String kDemoOwnerPassword = 'demo';
