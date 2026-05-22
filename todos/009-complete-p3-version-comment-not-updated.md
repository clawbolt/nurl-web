---
status: complete
priority: p3
issue_id: 009
tags: [code-review, documentation, nurl]
dependencies: []
---

# Problem Statement

The refactoring changed the internal structure significantly (6 new helper functions, config resolution changes, streaming shutdown fix) but the version is still `0.2.0` and there's no indication that this is a different revision. If a user reports a bug, there's no way to tell which `0.2.0` they're running.

## Findings

**Evidence:** Line 136:
```
: __NURL_APP_VERSION s `0.2.0`
```

And the file header line 1:
```
// stdlib/ext/nurl_app.nu — high-level web framework for NURL.  v0.2.0
```

The README also references `0.2.0`.

**Affected files:** `stdlib/ext/nurl_app.nu` lines 1, 136

## Proposed Solutions

### Option A: Bump to 0.2.1
- **Pros:** Distinguishes this revision from the pre-refactoring 0.2.0
- **Cons:** None meaningful
- **Effort:** S
- **Risk:** None

### Option B: Keep 0.2.0 (internal refactor, no API change)
- **Pros:** No version churn for non-breaking changes
- **Cons:** Can't distinguish builds
- **Effort:** None
- **Risk:** None

## Recommended Action

Option A — bump to 0.2.1 to distinguish the refactored version.

## Acceptance Criteria

- [ ] Version string updated in file header, `__NURL_APP_VERSION`, and README

## Work Log

- 2026-05-23: Found during post-fix review

## Resources

- stdlib/ext/nurl_app.nu
- README.md
