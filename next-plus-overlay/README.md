# TAIF PLUS 1.3.0

iOS 15+ app library and on-device IPA signing, derived from NEXT PlUS 1.2.1.

- Separate bundle identifier: `app.taifplus.store`.
- All first-party screens and both icon asset sets use TAIF PLUS.
- The attached 20,419-entry JSON catalog is shipped in the app, decoded offline, and indexed with the existing catalog cache/index optimizations.
- The built-in repository is hidden from source management and cannot be removed through RepositoryStore. User-added sources remain manageable.
- This is a bundled catalog snapshot. New catalog versions require an app update until the owner provides a persistent live feed.
- Source URLs are not secrets; hidden means absent from the management interface.
- Existing on-device certificate/profile checks, native signing, automatic iOS installation request, and export remain.
- Offline subscriptions use the separate TAIF PLUS app identity and owner-only issuer; private keys are never in source or IPA.

The GitHub workflow assembles the pinned upstream engine and this overlay, expands `idk-catalog.json.gz` into the app bundle, validates the real service lifecycle, native signing, transport, packaged deployment target and identity, and captures the simulator interface.

Retain the upstream source licenses. This app retains the original signing engine license obligations.

## 1.1.0

- Entry order is subscription activation, local P12/mobileprovision verification, then the store.
- Existing subscribers keep their activation on updates; remembered valid credentials are rechecked automatically on launch.
- The credential gate checks P12 opening/password, file parsing, expiry and team compatibility. It does not claim an online Apple revocation or device-registration check.
- The heavy catalog store is mounted only after both gates pass.
- Catalog and search retain 30 visible matches initially, extending the visible window by 30 on scroll or the explicit load-more button. A search scans the entire catalog, not only the visible page.
- The JSON metadata snapshot is still decoded locally once; paging limits list rows and associated icon loads, rather than changing the JSON into a remote paged API.
- New navy/cyan TAIF PLUS icon. Bundle ID and TAIF1 license public key remain unchanged.

## 1.2.0

- Prepared signing reuses the exact extraction already inspected for encrypted Mach-O files. A one-shot sidecar binds the private working folder to the original archive file identity; stale, replayed or escaped paths are rejected. Legacy inspection/signing remain available.
- Swift Release uses -O/whole-module compilation and native Release uses -O2. Debug remains unoptimized for previews.
- Optional real download/signing notifications are permission-gated and bounded to 20-percent download changes. A finite UIKit background task covers the operation; expiry cancels it and ends the assertion.
- The standard iOS installation confirmation still opens after signing through the existing manifest endpoint. Network speed, iOS acceptance and unlimited background signing are not promised.
- Buyer certificate automation is documented in Docs/BuyerEnrollment.ar.md; no fictional certificate service or private-key distribution backend has been activated.

- Duplicate buttons in the store and signed library append two unused lowercase letters to the actual inspected IPA bundle identifier, sign a distinct display name, and keep the input archive unchanged. All 676 two-letter combinations are collision-checked against this installation's signing history. iOS acceptance still depends on certificate/profile compatibility.

## 1.3.0

- Compact branded store with a navy hero, cyan/blue actions, denser application rows, and floating navigation dock.
- Installing from the store stays on the store. A real transfer HUD shows the app icon/name, measured percentage, downloaded/total bytes and cancel control. Tapping it opens library details.
- Local notification bodies now contain the same measured bytes and a text progress meter, plus an app-icon attachment where available. An iOS Settings shortcut is provided for notification permission.
- Unknown response lengths never show invented percentages. Stage changes distinguish downloading, inspection, signing and readiness.
- The simulator download-hud screenshot is explicitly labelled as a UI preview; it does not claim a completed real download or a physical-device notification test.
