# Signing identifier compatibility

NEXT PlUS 1.1.2 treats a textual difference between an app bundle identifier
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

NEXT PlUS keeps the app's existing bundle identifier and passes the selected
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
