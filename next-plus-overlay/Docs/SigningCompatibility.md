# Signing identifier compatibility

TAIF PLUS 1.1.2 treats a textual difference between an app bundle identifier
and a provisioning profile application identifier as a diagnostic, rather than
a reason to reject the operation before zsign runs.

The user-provided Zsign 4.0 IPA was inspected locally. Its Info.plist bundle
identifier differs from the application identifier in both its embedded profile
and signed XML entitlements. This is direct evidence that the previous preflight
rule did not represent the supplied application's signed structure. It does not,
by itself, prove which signing options are enabled on the user's device.

The app also contains references to the Ksign project. Its public signing handler
passes the certificate, profile, and optional custom bundle identifier separately:
https://github.com/Nyasami/Ksign/blob/main/Ksign/Utilities/Handlers/ZsignHandler.swift

TAIF PLUS keeps the app's existing bundle identifier and passes the selected
profile to the existing signing engine. It does not rewrite all apps to the
profile's identifier or modify the signed profile to add wildcard permissions.
Certificate loading, password, expiry, and team checks remain in place. The
profile's identifier is displayed as a signing identifier, not an exhaustive
prediction of whether iOS will accept installation.

The native regression test signs two fixture apps with distinct bundle IDs using
one explicit profile, checks that both IDs remain distinct, checks profile bytes
are unchanged, checks signed entitlements retain the profile identity, and verifies
executable/resource/entitlement hashes and the cryptographic CMS signature.

Fixtures use disposable test certificates. Passing these tests demonstrates
signing output correctness under the tested conditions, not Apple trust or actual
installation on the user's iPhone. A physical-device test with their certificate
and profile is still required.

## iOS 15 and automatic installation (1.2.0)

The active app targets iOS 15.0. Navigation uses NavigationView, IPA export uses
UIActivityViewController, and activation uses TextEditor. Certificate, profile,
and source forms use iOS 15 APIs. Legacy screens remain in source but are not
compiled into the active app. The loopback server uses NSLock instead of the
iOS-16-only OSAllocatedUnfairLock.

After a successful signing output is validated and recorded in the library, the
coordinator calls the existing installer automatically. Download, credential,
archive, and signing failures do not request installation. iOS confirmation is
still required. Signed files remain available for retry and sharing.

The packaging test checks the actual Info.plist and native Mach-O deployment
versions. This is a deployment/availability check, not a physical iOS 15 device
test. The current CI simulator runtime may be newer than iOS 15.

