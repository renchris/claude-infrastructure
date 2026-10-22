# DRAFT (not opened): bats-core upstream PR

**Title:** Run bats-core's own libexec scripts through `"$BASH"` instead of exec'ing them by path

## Problem

On macOS 15.x, every time the kernel execs a `#!` script by path, it keeps about one 1 KiB kalloc
element until reboot. In `exec_activate_image` (xnu `bsd/kern/kern_exec.c`), `exec_shell_imgact`
returns `-3` for a `#!` file, and the kernel records the script vnode and its MAC label
(`ip_scriptvp`, `ip_scriptlabelp`). Later, `exec_handle_sugid` passes the script vnode to every MAC
policy's `cred_label_update_execve` hook, and that is where the element is allocated and never
freed. An explicit interpreter (`bash script`) never takes the `-3` branch, so it retains nothing.
Measured on macOS 15.8.1 (24H32), n=3000: 1.098 ± 0.104 elements per `#!` exec,
against 0.007 ± 0.101 for `/bin/bash script`. A busy machine reaches about 20 GiB and panics.

bats-core execs its own `#!` files by path or by name for every file and every test. In one 38-minute
census window on a machine running bats suites, the kernel `#!` execs of bats-core internals were:
`bats-exec-test` 1268, `bats-exec-file` 116, `bats-preprocess` 85, `bats` 82, and
`bats-exec-suite`, `bats-format-cat` and `bats-gather-tests` 80 each. So every Mac bats user pays
about one element per test, plus a few per file, until reboot.

## Change

Every internal call in the patch below runs its libexec file as `"$BASH" <full path>`.
The formatter variables become arrays so the interpreter and the path travel together; a formatter
given as an absolute path still runs by path, as-is. No other logic changes.

## Why this is behavior-neutral

- Every one of these files starts with `#!/usr/bin/env bash`, and the caller is already running under
  that same bash, so `$BASH` is the interpreter `env` would have found, minus one kernel exec.
  bats-core already requires bash >= 3.2, and `$BASH` is set in every bash.
- `$0` and `BASH_SOURCE[0]` are the same full path either way, so `bats_readlinkf` and
  `BATS_LIBEXEC` resolve the same.
- Exported functions and variables are inherited exactly as before.
- Side benefit: the libexec files no longer need their exec bit, which helps packagers whose archive
  or copy step drops it. A copy of the tree with `chmod a-x libexec/bats-core/*` passes with this
  patch, and the unpatched tree fails at once with `Permission denied` (rc 126).

**Behavior changes upstream may ask about:**

1. `bats-exec-suite`, `bats-exec-file`, `bats-gather-tests` and `bats-format-*` were found by name on
   `PATH`. `bats` puts `$BATS_LIBEXEC` first on `PATH`, so in practice that was always the libexec
   copy. With this patch, shadowing them through `PATH` is no longer possible at all (for example,
   from a GNU parallel shell whose startup files reorder `PATH`). We think that is a fix, but it is
   a change.
2. If a report formatter fails, `bats_tee`'s error message prints `$*`, which now begins with the bash
   path.

## Test idea

A test that copies `bin/`, `libexec/` and `lib/` into a temp dir, runs `chmod a-x` on
`libexec/bats-core/*`, then runs `bash <tmp>/bin/bats` over a small fixture with `-F tap`,
`-F pretty`, `-F junit`, `--report-formatter junit`, a failing test (expects rc 1) and, when GNU
parallel is present, `-j 2`. Any internal call left exec'ing by path fails with rc 126. That makes it
a regression guard that needs no macOS and no kernel instrumentation.

## Patch (against v1.13.0, `3bca150ec86275d6d9d5a4fd7d48ab8b6c6f3d87`)

Verified: applies with `patch -p1` to the v1.13.0 tarball. The GNU parallel path (`-j`) was not run,
because `parallel` was not installed on the test machine.

```diff
diff -u a/bin/bats b/bin/bats
--- a/bin/bats
+++ b/bin/bats
@@ -74,2 +74,2 @@
 export -f bats_readlinkf
-exec env BATS_ROOT="$BATS_ROOT" BATS_LIBDIR="${BATS_BASE_LIBDIR:-lib}" "$BATS_ROOT/libexec/bats-core/bats" "$@"
+exec env BATS_ROOT="$BATS_ROOT" BATS_LIBDIR="${BATS_BASE_LIBDIR:-lib}" "$BASH" "$BATS_ROOT/libexec/bats-core/bats" "$@"
diff -u a/lib/bats-core/preprocessing.bash b/lib/bats-core/preprocessing.bash
--- a/lib/bats-core/preprocessing.bash
+++ b/lib/bats-core/preprocessing.bash
@@ -11,3 +11,3 @@
   # shellcheck disable=SC2153
-  CHECK_BATS_COMMENT_COMMANDS=1 "$BATS_ROOT/libexec/bats-core/bats-preprocess" "$BATS_TEST_FILENAME" >"$BATS_TEST_SOURCE"
+  CHECK_BATS_COMMENT_COMMANDS=1 "$BASH" "$BATS_ROOT/libexec/bats-core/bats-preprocess" "$BATS_TEST_FILENAME" >"$BATS_TEST_SOURCE"
 }
diff -u a/libexec/bats-core/bats b/libexec/bats-core/bats
--- a/libexec/bats-core/bats
+++ b/libexec/bats-core/bats
@@ -395,5 +395,5 @@
   bats_check_formatter "$formatter"
-  interpolated_formatter="$formatter"
+  interpolated_formatter=("$formatter")
 else
-  interpolated_formatter="bats-format-${formatter}"
+  interpolated_formatter=("$BASH" "$BATS_LIBEXEC/bats-format-${formatter}")
 fi
@@ -426,5 +426,5 @@
   bats_check_formatter "$report_formatter"
-  interpolated_report_formatter="${report_formatter}"
+  interpolated_report_formatter=("${report_formatter}")
 else
-  interpolated_report_formatter="bats-format-${report_formatter}"
+  interpolated_report_formatter=("$BASH" "$BATS_LIBEXEC/bats-format-${report_formatter}")
 fi
@@ -516,10 +516,10 @@
 if [[ -n "$report_formatter" ]]; then
-  exec bats-exec-suite "${flags[@]}" "${filenames[@]}" |
-    bats_tee "${BATS_REPORT_OUTPUT_DIR}/${BATS_REPORT_FILENAME}" "$interpolated_report_formatter" "${report_formatter_flags[@]}" |
+  exec "$BASH" "$BATS_LIBEXEC/bats-exec-suite" "${flags[@]}" "${filenames[@]}" |
+    bats_tee "${BATS_REPORT_OUTPUT_DIR}/${BATS_REPORT_FILENAME}" "${interpolated_report_formatter[@]}" "${report_formatter_flags[@]}" |
     bats_test_count_validator |
-    "$interpolated_formatter" "${formatter_flags[@]}"
+    "${interpolated_formatter[@]}" "${formatter_flags[@]}"
 else
-  exec bats-exec-suite "${flags[@]}" "${filenames[@]}" |
+  exec "$BASH" "$BATS_LIBEXEC/bats-exec-suite" "${flags[@]}" "${filenames[@]}" |
     bats_test_count_validator |
-    "$interpolated_formatter" "${formatter_flags[@]}"
+    "${interpolated_formatter[@]}" "${formatter_flags[@]}"
 fi
diff -u a/libexec/bats-core/bats-exec-file b/libexec/bats-core/bats-exec-file
--- a/libexec/bats-core/bats-exec-file
+++ b/libexec/bats-core/bats-exec-file
@@ -235,3 +235,3 @@
   for ((try_number = 1; should_try_again; ++try_number)); do
-    if "$BATS_LIBEXEC/bats-exec-test" "$@" "$try_number"; then
+    if "$BASH" "$BATS_LIBEXEC/bats-exec-test" "$@" "$try_number"; then
       should_try_again=0
diff -u a/libexec/bats-core/bats-exec-suite b/libexec/bats-core/bats-exec-suite
--- a/libexec/bats-core/bats-exec-suite
+++ b/libexec/bats-core/bats-exec-suite
@@ -140,3 +140,3 @@
 touch "$TESTS_LIST_FILE"
-gather_tests_output=$(TESTS_LIST_FILE="$TESTS_LIST_FILE" filter="$filter" nfilter="$nfilter" filter_status="$filter_status" bats-gather-tests "${gather_tests_flags[@]}" -- "$@")
+gather_tests_output=$(TESTS_LIST_FILE="$TESTS_LIST_FILE" filter="$filter" nfilter="$nfilter" filter_status="$filter_status" "$BASH" "$BATS_LIBEXEC/bats-gather-tests" "${gather_tests_flags[@]}" -- "$@")
 test_count=$(grep -c ^ "$TESTS_LIST_FILE" || true) # don't fail here when there are no tests
@@ -313,3 +313,3 @@
   # because parallel can only quote it as one
-  "${parallel_binary_name}" "${parallel_flags[@]}" -- "bats-exec-file" "$(printf "%q " "${flags[@]}")" "{#}" "{}" "$TESTS_LIST_FILE" <<< "$(printf "%s\n" "${BATS_UNIQUE_TEST_FILENAMES[@]}")" 2>&1 || bats_exec_suite_status=1
+  "${parallel_binary_name}" "${parallel_flags[@]}" -- "$(printf "%q %q" "$BASH" "$BATS_LIBEXEC/bats-exec-file")" "$(printf "%q " "${flags[@]}")" "{#}" "{}" "$TESTS_LIST_FILE" <<< "$(printf "%s\n" "${BATS_UNIQUE_TEST_FILENAMES[@]}")" 2>&1 || bats_exec_suite_status=1
 else
@@ -322,3 +322,3 @@
     fi
-    bats-exec-file "${flags[@]}" "$file_index" "$filename" "${TESTS_LIST_FILE}" || bats_exec_suite_status=1
+    "$BASH" "$BATS_LIBEXEC/bats-exec-file" "${flags[@]}" "$file_index" "$filename" "${TESTS_LIST_FILE}" || bats_exec_suite_status=1
     if (( BATS_ABORT_ON_FAILURE && bats_exec_suite_status > 0 )); then
```
