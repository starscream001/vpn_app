# Corresponding sources for FoxWay 0.2 preview

FoxWay's original code is MIT. Combined binaries incorporating GPL components are distributed under the applicable GPL terms; see LICENSE-gpl3.txt and each upstream notice. FoxWay is not affiliated with SagerNet, Amnezia or Hiddify.

Every native preview release must include `FoxWay-corresponding-source.tar.gz` alongside the binaries. It contains the application at the exact source commit, full pinned native core source archives, verified Go module source archives and Dart plugin sources/notices. The application archive includes vendored Apple AWG, modified AWG tools, iOS plugin, build scripts and lockfiles. The release's automatically generated GitHub source archive is also available.

Pinned native origins:

- sing-box 1.14.4: SagerNet/sing-box, commit c005f35300ce76427dc285481ec5695f5b179cd2. GPL-3.0-or-later with upstream naming notice. Official desktop release checksums: scripts/sing_box_assets.json. Build flags/workflow are in that source archive.
- libbox 1.14.4: same sing-box source; upstream QUSAD-prod/sing_box build recipe copied into packages/sing_box_ios/scripts, LIBBOX_VERSION and XCFramework SHA in its Package.swift. The plugin's native source and GPL notices are vendored. Build with scripts/build_libbox.sh apple --install on a full Xcode host.
- Amnezia Apple: amnezia-vpn/amneziawg-apple commit 9d5ee60edefa95b933a738dd7cda671dd18021fc, MIT; selected sources and local changes recorded under native/amnezia-apple. Build Go static bridge with the arguments in .github/workflows/build.yml before Flutter/Xcode.
- Amnezia Windows/Go: v3.1.20260814, pinned go.mod/go.sum under native/windows-awg and native/awg-cli; MIT. Windows wrapper builds with go build in its folder; Linux CLI builds the named upstream main package. No driver/service is installed during builds.
- Amnezia tools: commit ee0f0a9aa34ff0a0da4b3433b9512781cfe02843, GPL-2.0. Source, COPYING and changes included under native/amnezia-tools. Build with make -C native/amnezia-tools/src.
- AndroidLibXrayLite v26.10.17: 1be1e621be15702da7b7faf16ef83f2493c5aa01, LGPL-3.0; source archive includes build scripts and exact Xray Go dependency. Rebuild AAR following upstream recipe, substitute in the flutter_v2ray Android Gradle dependency and rebuild the APK. FoxWay imposes no restriction on reverse engineering for debugging these modifications.
- Android AWG wrapper: Maven com.zaneschepke:amneziawg-android:2.3.7; Apache-2.0 wrapper and MIT native core. Android dependency versions and original notices are listed in docs/LICENSES.md. Maven sources are additionally included in the source bundle.
- Wintun 0.14.1: official wintun.net archive verified by SHA-256, original precompiled driver and binary license in Windows bundle. Source: https://git.zx2c4.com/wintun/ . Not a FoxWay-modified driver.

Go dependency archives preserve original module licenses. To restore offline module inputs, use go-module-manifest.json to map module/version to its .zip/.mod/.info in go-modules; Go build otherwise obtains the same versions from the public module proxy and verifies go.sum. Flutter 3.47.9 and Go 1.26 (AWG) / Go 1.27 (AndroidLibXrayLite source tooling) are build prerequisites; SDK/compiler/system libraries are separate standard toolchains. A complete byte-for-byte reproducibility or legal audit of every transitive native object has not been performed. Preserve all notices when redistributing.

Generate this bundle with `python3 scripts/bundle_sources.py` after `flutter pub get` on the source commit. The CI source job fails if any required source/module download fails; a release must not omit a failed source artifact. No VPN connection or server access is needed.
