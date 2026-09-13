// Version.swift
// Single marketing/build version for Info.plist, the menu "v…" chip, and
// the About sheet. scripts/build_app.sh greps the quoted semver below.
// Do not add a second 0.1.0 literal in build_app.sh or MagicPadServer.swift.

enum AppVersion {
    static let string = "0.1.0"
}
