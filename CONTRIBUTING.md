# Contributing to Pictr

Thanks for helping. Pictr is free and open source under the [MIT License](LICENSE).

## How changes land

`main` is protected. Every change arrives as a pull request:

1. Fork the repository and create a branch from `main` (`fix/deck-undo`, `feat/ipad-layout`).
2. Make the change, with tests for any logic you touch.
3. Run the checks below, then open a pull request against `main`.
4. A maintainer reviews it. Pull requests are merged by squash or rebase; history stays linear.

Open an [issue](https://github.com/Acker-Cloud/pictr/issues) first for anything large, so we can agree on the shape before you build it.

## Checks

```sh
xcodegen generate
xcodebuild -project Pictr.xcodeproj -scheme Pictr \
  -destination 'platform=iOS Simulator,name=<simulator>' -only-testing:PictrTests test
xcodebuild -project Pictr.xcodeproj -scheme Pictr -destination 'generic/platform=iOS' build
grep -rnE "URLSession|NWConnection|import Network|URLRequest|PrivateCloudCompute" Pictr   # must print nothing
```

The build treats warnings as errors. If you change the interface and have an iPhone, also run
`PictrUITests/DeviceSmokeTests` on it; it only opens screens and never keeps, queues or deletes.

## Ground rules

- **Privacy is the product.** No networking code, no analytics, no third-party SDKs. Analysis
  stays on the device.
- **Never delete without Apple's confirmation**, and never preselect suggestions for the user.
- Match the code around you. `CLAUDE.md` has the conventions and the mistakes already made once.
- Commit with your GitHub noreply address if you'd rather not publish your email.

## Reporting bugs and privacy issues

Bugs and feature requests go in [issues](https://github.com/Acker-Cloud/pictr/issues). For a
privacy or security problem, email [support@acker.cloud](mailto:support@acker.cloud) instead of
opening a public issue.
