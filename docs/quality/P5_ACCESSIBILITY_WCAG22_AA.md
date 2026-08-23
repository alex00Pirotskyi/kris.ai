# P5 Accessibility — WCAG 2.2 AA Closure Checklist

**Task:** P5-012  
**Scope:** desktop Kristin Experience shell, primary Chat/Run/Verification/Evidence flows, Owner Mode failure state, command controls and shared P5 design system.  
**Standard:** applicable WCAG 2.2 Level A/AA success criteria for a native desktop UI, mapped to Flutter semantics and platform accessibility behavior.

## Automated closure gates

| Area | Evidence | Required state |
|---|---|---|
| Keyboard operation | `test/product/p5_information_architecture/p5_accessibility_test.dart`, `test/product/p5_ux_regression_gate_test.dart` | PASS |
| Focus traversal | Tab-to-primary-action coverage in `p5_accessibility_test.dart` | PASS |
| Programmatic names/state | semantics-label coverage for navigation, Owner Mode and capability state | PASS |
| Text resize/reflow | `test/product/p5_accessibility_compliance_test.dart` at 200% on wide and compact surfaces | PASS |
| Contrast | `test/product/p5_design_tokens_test.dart` deterministic high-contrast checks | PASS |
| Reduced motion | design-token and compliance tests require zero semantic/theme transition durations | PASS |
| Pointer target floor | automated shared-control measurement requires >=44x44 logical pixels | PASS |
| Failure-state clarity | P5-014 verifies blocked Owner Mode exposes a normalized diagnostic rather than raw exception text | PASS |
| Visual regression | Linux deterministic P5-014 golden baseline | PASS |

## Manual platform checks

These checks cannot be truthfully replaced by widget tests. A release-candidate acceptance packet must record the tester, platform build, assistive technology and result.

| Check | Windows | macOS | Blocking rule |
|---|---|---|---|
| Screen-reader reading order and names | Narrator | VoiceOver | No unlabeled primary control or misleading state |
| Keyboard-only end-to-end task | Standard keyboard | Standard keyboard | No keyboard trap; every primary action reachable |
| Visible focus at 100% / 200% text | System scaling | System scaling | Focus indicator never disappears behind clipping |
| High-contrast/system contrast mode | Windows Contrast Themes | Increase Contrast | Primary text/action/state remains distinguishable |
| Reduced-motion system preference | Animation effects off | Reduce motion | No required information communicated only by motion |
| Error/recovery announcement | Narrator | VoiceOver | Blocking failures have readable cause + recovery action |

## WCAG mapping used for P5 closure

The automated and manual checks cover the applicable intent of 1.3.1, 1.4.3, 1.4.4, 1.4.10, 1.4.11, 2.1.1, 2.1.2, 2.4.3, 2.4.7, 2.4.11, 2.5.8, 3.2.1, 3.2.2, 3.3.1, 3.3.2, 4.1.2 and 4.1.3. Native desktop semantics that have no meaningful web analogue are tested against the platform accessibility tree rather than treated as automatically satisfied.

## Completion rule

P5-012 is complete only when all automated gates are green on the exact candidate and the Windows/macOS manual platform rows above are recorded without an unresolved critical accessibility blocker. Missing manual evidence is **not** a pass.
