# TODO

Items noted during the 2.7.3 bug sweep (Task 11) that are non-trivial, unverifiable
without a provisioned build/simulator machine, or out of scope to fix in this pass.
No silent skips — tracked here per the sweep's fix-or-TODO policy.

## Pre-existing force-unwraps noted during reader code-path audit (low risk, not caused by 2.7.3)

- `iOS/UI/Reader/Views/ReaderTextViewController.swift:575` — `sections.last!` inside an
  `await MainActor.run` block when appending an inline chapter-transition view. Guarded by
  an earlier `guard !sections.isEmpty else { return }`-style check upstream, so believed safe
  today, but the force-unwrap itself offers no protection if that invariant ever changes.
  Consider replacing with a `guard let lastSection = sections.last else { return }`.

- `iOS/UI/Reader/Views/ReaderWebtoonPageNode.swift:44` — `(progressNode.view as? CircularProgressView)!`
  force-unwrap of an ASDisplayNode's backing view cast. Low risk (the node always vends this
  view type in practice) but a nil view during an unusual node lifecycle state would crash.
  Consider a safer fallback or an explicit precondition with a diagnostic message.

## Escalation: real build/test/manual-pass validation still required

This machine has no iOS Simulator runtime and no iOS 26.5 platform SDK installed, so
`xcodebuild build` / `xcodebuild test` could not be run for this task (confirmed failing,
see task-11-report.md for the exact error). All verification in Task 11 was done via
`swiftc -parse` across all Swift sources plus manual code-path tracing. **A real
`xcodebuild build` and `xcodebuild test -destination 'platform=iOS Simulator,name=iPhone 15'`
run (all green, including `MihonBackupTests`), plus a manual on-device/simulator pass through
library, browse, reader, backup (native + Mihon), translation, and settings, must happen on a
provisioned machine before this release ships.**
