# Lead notes (CC 2.1.293, verified in /tmp/cc293-strings.txt)
Operator example 2026-10-11: workflow agent "lr-decisions-research" Bash `bash -c '...T() { ...; "$@" ...}; ... bash -c "$H" _ "$s"'`
-> "This shell -c script runs rm and could not be checked" + 2:00 auto-deny countdown. Script contains NO rm.
Mechanism: k_e()/ian() inline-shell scanner; when a segment cannot be fully parsed, g_e(script) is checked:
  g_e fires if a token is rm/rmdir (with other args), OR any word STARTING WITH `$` in command position
  (h===0 or after a wrapper in UYe), OR VAR=…/rm assignment, OR oan/ran token test.
  -> h_e(): {behavior:ask, safetyCheck, circuitBreaker:"dangerousRemoval", classifierApprovable:false}
  -> wln() adds autoDenyWindow (tengu_splendid_horizon timeoutMs 120000, maxDialogTimeouts 3/session).
  ASr(): variable-target rm in shell -c => "cannot be auto-allowed by permission rules. Pass a literal path, or guard the value with ${NAME:?}."
nan() (depth-cap fallback) also fires on brace expansion {a,b} / {1..3}.
Telemetry event for shape: tengu_bash_dangerous_rm_shape {shape: inline_shell_unchecked | inline_shell_script}.
Operator-only env kill switches (remove a safety rail; NOT ours to flip): CLAUDE_CODE_DISABLE_DANGEROUS_RM_TIMEOUT,
  CLAUDE_CODE_DISABLE_SUBSTITUTION_RM_PROMPT, CLAUDE_CODE_DISABLE_INLINE_SHELL_RM_PROMPT, CLAUDE_CODE_DISABLE_POWERSHELL_CMD_RM_DENY.
Implication: allow rules cannot fix this class. Levers: PreToolUse deny-with-recipe before the dialog (instant, not 2 min),
  model guidance (no `bash -c` wrapper with "$@"/$cmd dispatchers; write multi-line bash to a file and run `bash /tmp/x.sh`;
  rm targets literal or ${VAR:?}).
