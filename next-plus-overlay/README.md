# idk plus 1.1.0

iOS 15+ app library and on-device IPA signing, derived from NEXT PlUS 1.2.1.

- Separate bundle identifier: `app.idkplus.store`.
- All first-party screens and both icon asset sets use idk plus.
- The attached 20,419-entry JSON catalog is shipped in the app, decoded offline, and indexed with the existing catalog cache/index optimizations.
- The built-in repository is hidden from source management and cannot be removed through RepositoryStore. User-added sources remain manageable.
- This is a bundled catalog snapshot. New catalog versions require an app update until the owner provides a persistent live feed.
- Source URLs are not secrets; hidden means absent from the management interface.
- Existing on-device certificate/profile checks, native signing, automatic iOS installation request, and export remain.
- Offline subscriptions use the separate idk plus app identity and owner-only issuer; private keys are never in source or IPA.

The GitHub workflow assembles the pinned upstream engine and this overlay, expands `idk-catalog.json.gz` into the app bundle, validates the real service lifecycle, native signing, transport, packaged deployment target and identity, and captures the simulator interface.

Retain the upstream source licenses. This app retains the original signing engine license obligations.

## 1.1.0

- Entry order is subscription activation, local P12/mobileprovision verification, then the store.
- Existing subscribers keep their activation on updates; remembered valid credentials are rechecked automatically on launch.
- The credential gate checks P12 opening/password, file parsing, expiry and team compatibility. It does not claim an online Apple revocation or device-registration check.
- The heavy catalog store is mounted only after both gates pass.
- Catalog and search retain 30 visible matches initially, extending the visible window by 30 on scroll or the explicit load-more button. A search scans the entire catalog, not only the visible page.
- The JSON metadata snapshot is still decoded locally once; paging limits list rows and associated icon loads, rather than changing the JSON into a remote paged API.
- New navy/cyan idk plus icon. Bundle ID and IDK1 license public key remain unchanged.
