# Contributing

Thanks for helping with Sticky Windows. Bug reports, quirk findings (see QUIRKS.md), and pull requests are welcome.

## Before you start

- Build with Xcode 16 or later on macOS 15 or later; see README → Building. The project is generated from `project.yml` with XcodeGen, so edit that, not the `.xcodeproj`.
- Keep the code in the style of the files around it: Swift 6 with strict concurrency, `@MainActor` for anything touching AppKit or the Accessibility API.
- Quit the app with ⌘Q, not Xcode's Stop button, so parked windows are restored while you work.

## Licensing of contributions

Sticky Windows is licensed under the PolyForm Noncommercial License 1.0.0 (see LICENSE and NOTICE). By submitting a contribution you agree that:

1. You wrote it, or have the right to submit it.
2. It is licensed to the project under the same license.
3. The Shirley Company LLC, as the project's maintainer and copyright holder, may also relicense the project, including your contribution, under other terms, for example to grant commercial permission to a third party.

If you can't agree to that, please open an issue describing the change instead of a pull request.
