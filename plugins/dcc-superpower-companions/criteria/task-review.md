# Task Review - Verifier Criteria

Applied by dcc-superpower-companions:dispatching-tiered-implementers when a task
reviewer scores one task's implementation.

## Ground Truth Note

Do NOT trust the implementer's report. It is a set of unverified claims about
the code, and implementers routinely declare success on work that is incomplete,
untested, or subtly wrong. Trust the diff and the command output quoted in the
report over any narration of them. A stated rationale - "left it per YAGNI",
"kept it simple deliberately" - is the implementer grading its own work and
never raises a score.

Evidence you cannot see is not evidence that does not exist. If the report looks
truncated, re-read it at its stated path before treating it as missing.

## Criteria

### Spec Compliance {#spec}

Compare the diff against the task brief, requirement by requirement. Score HIGH
when every requirement in the brief has a corresponding change in the diff and
nothing beyond the brief was built. Score LOW when a requirement is missing,
when a requirement was claimed in the report but has no hunk in the diff, when
the right feature was built the wrong way, or when unrequested work appears -
extra abstraction, speculative options, nice-to-haves. If the brief lists
several files each with its own change, a listed file the diff never touches is
a LOW signal no matter how clean the rest of the batch is. Ignore code quality,
test design, and whether the tests were actually run; other criteria own those.

### Empirical Verification {#verification}

Look at the commands the report says were run and the output it quotes, not at
what the report concludes from them. Score HIGH when the implementer ran tests
covering exactly the code it changed, quoted the output, and the quoted output
supports the claim - and, where the brief required TDD, when a failing run is
shown before the implementation and a passing run after it. Score LOW when
success is declared with no command shown, when the quoted output does not
actually say what the report claims it says, when a traceback or a warning in
the quoted output is passed over, or when the code was edited again after the
last successful run so the final state is untested. Test output that is not
pristine is a LOW signal. Ignore whether the tests are well designed; that
belongs to Code Quality.

### Code Quality {#quality}

Review the diff as an experienced reviewer would. Score HIGH when the change is
correct, each file has one clear responsibility, error paths are handled, and
the tests assert real behavior rather than mocks. Score LOW for semantic errors
the tests would not catch, swallowed errors, verbatim duplication of a logic
block, tests that assert nothing, silent regressions in code paths the brief did
not mention, or a new file that is already unwieldy. Judge the diff on its
technical merits, not on its length or apparent effort. Ignore requirements
coverage, which Spec Compliance owns, and ignore pre-existing problems in code
this diff does not touch.
