---
status: complete
priority: p3
issue_id: 008
tags: [code-review, readability, nurl]
dependencies: []
---

# Problem Statement

In `app_run` (lines 856-858) and `app_run_streaming` (lines 1011-1013), local `timeout` and `wk` variables are declared as reads from already-resolved App fields. These locals exist only to pass to `server_new_with_timeout` / `server_run_pool` / `parse_request_head`. They're fine functionally but add two lines that just alias App fields.

## Findings

**Evidence:** `app_run` lines 856-858:
```
: i timeout . app idle_timeout_ms
: i wk . app workers
```

These could be inlined at the call sites: `. app idle_timeout_ms` and `. app workers` directly. But NURL may not support dot-access expressions as function arguments — the locals may be required by the language.

**Affected files:** `stdlib/ext/nurl_app.nu` lines 856-858, 1011-1013

## Proposed Solutions

### Option A: Keep as-is
- **Pros:** Clear, readable, may be required by NURL syntax
- **Cons:** Two extra lines per function
- **Effort:** None
- **Risk:** None

### Option B: Inline if NURL supports it
- **Pros:** Fewer locals
- **Cons:** May not be syntactically valid
- **Effort:** S
- **Risk:** Low

## Recommended Action

Option A — keep as-is. The locals are clear and may be syntactically necessary.

## Acceptance Criteria

- [ ] Code compiles and runs correctly

## Work Log

- 2026-05-23: Found during post-fix review

## Resources

- stdlib/ext/nurl_app.nu
