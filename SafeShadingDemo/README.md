# Safe PDF Shading Demo

This is a benign SwiftUI sample that renders a normal, bounded Core Graphics gradient and exports a standards-compliant PDF.

## Cloud build

The GitHub Actions workflow at `.github/workflows/ios-ipa.yml` uses GitHub's Xcode 27 hosted runner. Run it from **Actions → Build safe iOS demo IPA → Run workflow**.

The workflow uploads an unsigned IPA artifact. Use Sideloadly or another legitimate signing method with your own Apple account to sign it before installing on a device.

This project intentionally does not include malformed PDF objects, out-of-bounds parameters, or vulnerability-triggering code.
