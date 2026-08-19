# <Your Evaluation> - Verifier Criteria

Copy this file, replace the content, and keep the heading structure. A skill
hands a judge subagent the path to a file like this one; the judge has no other
context, so everything it needs to score must be in here.

Adapted from the criteria format in LLM-as-a-Verifier (arXiv:2607.05391).

## Ground Truth Note

One paragraph the judge sees on every evaluation. Use it to say which evidence
to trust, not what to conclude.

Do NOT trust the agent's self-assessment or its claims of success. Trust the
command output observed in the record over any narration of that output.

## Criteria

One third-level heading per criterion, 2 to 4 of them. Everything until the next
heading is that criterion's instruction. The judge scores each criterion
independently, which is why two narrow criteria beat one broad one.

Every heading pins an id in braces, as the two examples below do. The id is what
reports and skills refer to, so it must survive a reworded heading. Keep it
lowercase, with letters, digits, and underscores only.

Write each instruction so a stranger could score with it, in this order:

- say exactly WHERE to look - which files, commands, fields, or output
- say what should score HIGH
- say what should score LOW
- say what to IGNORE, so one criterion does not leak into another

The ignore clause is the one most often skipped and the one that does the most
work. Without it two criteria drift onto the same evidence and the score stops
carrying two independent readings.

### First Example Criterion {#first_example}

Look at <exact location>. Score HIGH when <observable property>. Score LOW when
<observable failure>, when the evidence is asserted rather than shown, or when
<the specific confusion this criterion exists to catch>. Ignore <what the
neighbouring criterion owns>.

### Second Example Criterion {#second_example}

Two criteria are the minimum, and this file carries two so that it satisfies the
format it documents. Replace both. Look at <a different location from the one
above>. Score HIGH when <observable property>. Score LOW when <observable
failure>. Ignore <what the first criterion owns> - naming it here is what keeps
the two scores independent.
