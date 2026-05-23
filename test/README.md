# nurl_app test suite

## Prerequisites

- NURL compiler (`nurlc`) available on PATH, or `./nurl.sh` wrapper at repo root
- NURL stdlib with HTTP stack modules

## Running tests

```bash
# Run all pure-logic tests
./test/test.sh

# Run all tests including network tests
NURL_NET_TESTS=1 ./test/test.sh
```

## Test files

| File | What it tests |
|------|---------------|
| `test_ctx_lifecycle.nu` | `__ctx_new`, `__ctx_free` |
| `test_ctx_accessors.nu` | All 12 Ctx request accessors |
| `test_ctx_response.nu` | All 9 response builders + pending headers |
| `test_helpers_internal.nu` | `__body_to_string`, `__search_pair`, `__group_path`, `__walk_mw` |
| `test_app_lifecycle.nu` | `app_new`, config, `app_use`, `app_static` |
| `test_routes.nu` | Route registration, groups, middleware snapshot |
| `test_dispatch.nu` | `__dispatch` — core pipeline, middleware, body limit, params |
| `test_hooks.nu` | Health endpoint, lifecycle hooks, `__prepare_run` |
| `test_net_*.nu` | Network integration tests (gated by `NURL_NET_TESTS=1`) |

## Adding new tests

1. Create `test/test_<name>.nu`
2. Import helpers: `$ \`test/test_helpers.nu\``
3. Each test function returns 0 (pass) or 1 (fail)
4. Aggregate in `@ main → i` using the failure counter pattern
5. The runner will discover and execute it automatically

## Network tests

Tests prefixed `test_net_` require real TCP connections. They are skipped
unless `NURL_NET_TESTS=1` is set. These tests start servers on high ports
and verify end-to-end HTTP behavior.

## Memory leak detection

Run tests under valgrind or ASAN to detect leaks:

```bash
# If using valgrind with nurlc-compiled binaries:
NURL_NET_TESTS=1 valgrind --leak-check=full ./test/test.sh
```
