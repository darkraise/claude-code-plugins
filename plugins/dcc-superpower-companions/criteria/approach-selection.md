# Approach Selection - Verifier Criteria

Applied by dcc-superpower-companions:selecting-approaches when a judge ranks
candidate approaches pairwise.

## Ground Truth Note

You are comparing two proposals, not grading essays. Judge what each approach
would actually do to this repository, using the files you can read. A proposal
that is well written but wrong for this codebase loses to a plainly stated one
that fits.

Do NOT reward a proposal for hedging. A candidate that lists several options
instead of committing to one has not answered the question, and its apparent
safety is an artifact of saying less.

Neither candidate is a default. If they are genuinely equivalent on a criterion,
score them equally rather than inventing a difference.

## Criteria

### Fit to This Codebase {#fit}

Read the files each approach names. Score an approach HIGH when it follows a
pattern this repository already uses, reuses what exists, and its named files
and interfaces actually match what is there. Score it LOW when it introduces a
second way to do something the repo already does one way, when it assumes files,
interfaces, or conventions that do not exist here, or when it would leave two
subsystems disagreeing about the same concept. Ignore how much work each
approach is; effort belongs to Simplicity.

### Cost of Being Wrong {#reversibility}

Look at what each approach commits to and how far that commitment reaches: the
files it names, the interfaces it fixes, and what later work would have to
build on it. Consider what happens if this approach turns out to be the wrong
choice six tasks later. Score HIGH when backing out is a revert - the approach
is additive, its blast radius is one place, and nothing downstream is built to
depend on its shape. Score LOW when it commits early to a data shape, a public
interface, a stored format, or a dependency that later work would have to be
rewritten around, and lower still when the commitment is invisible from the
call sites it constrains. Ignore whether the approach is likely to be wrong;
only how expensive it is if it is.

### Simplicity {#simplicity}

Read what each approach proposes to build, and the problem statement it is
answering. Score HIGH for the approach that a reader meeting this code for the
first time would understand fastest, and that solves exactly the stated
problem. Score LOW for machinery built for requirements nobody has stated,
configuration with one caller, indirection that adds a hop without adding a
boundary, or a general mechanism where a specific one was asked for. Fewer
moving parts wins ties. Ignore fit and reversibility, which the other criteria
own, and do not reward brevity that works by leaving a stated requirement
unaddressed.
