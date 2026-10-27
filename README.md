# TAIF PLUS 1.0.0

Independent iOS 15+ store with ruby, pure-white and charcoal appearance, persisted Light/Dark/System preference, on-device signing and a bundled catalog.

The workflow assembles the pinned upstream iStore engine, overlays this source and expands public assets. It builds the IPA, checks signing policy, appearance persistence, real transport, catalog lifecycle, native signing and packaged compatibility, then captures light and dark simulator screenshots.

This branch contains no owner private key, certificate, password or subscriber database. TAIF PLUS uses app.taifplus.store and its own verification public key, separate from idk plus.

Channel: https://t.me/tife_store
Owner: https://t.me/tife_store1
Developer: https://t.me/YG8_1

The activation service endpoint is prepared for a separate Cloudflare Worker taif-plus-panel. Long signed TAIF1 activation codes work offline; short codes and assigned certificate delivery require that Worker to be deployed.
