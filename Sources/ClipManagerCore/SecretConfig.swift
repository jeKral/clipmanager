import Foundation

/// Build-time HMAC secret injection.
///
/// The real secret is NEVER written into the repository. The checked-in
/// template below is `nil`. At build time `Scripts/inject-secret.sh`
/// (invoked by `make build` / `make run` / `make test`) replaces the value
/// with the contents of the `CLIP_LICENSE_SECRET` environment variable.
///
/// Without a secret the app fails closed: serials cannot be verified and
/// `LicenseStore.activate` reports the licensing system as unavailable.
public enum SecretConfig {
    // The line below is replaced in place by Scripts/inject-secret.sh — keep the marker `static let licenseSecret`.
    public static let licenseSecret: String? = nil
}
