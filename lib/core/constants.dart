/// App-wide constants. [kAppVersion] must match the release tag (vX.Y.Z) so the
/// self-updater can tell when a newer build is published.
const String kAppVersion = '1.8.7';
const String kGithubOwner = 'ZubaraX';
const String kGithubRepo = 'aurora-vpn';

String get kReleasesApi =>
    'https://api.github.com/repos/$kGithubOwner/$kGithubRepo/releases/latest';
String get kReleasesPage =>
    'https://github.com/$kGithubOwner/$kGithubRepo/releases/latest';
