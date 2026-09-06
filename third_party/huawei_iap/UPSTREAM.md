Source: https://gitcode.com/CPF-Flutter/flutter_packages.git
Branch: br_in_app_purchase-v3.2.3_ohos (Flutter 3.41)
Commit: 5e6abec7d3687b3904a403c7a38402ced24d2e60
Vendored application and OHOS packages, with upstream licenses retained.
Local patches: sibling path dependency; per-transaction full signed receipt through
ArkTS and Dart serialization (never use the mutable global last receipt for verification).
Examples/tests omitted from vendoring; application integration tests cover checkout.
Additional patches: forward account binding as signed developerPayload; expose subscription management.
