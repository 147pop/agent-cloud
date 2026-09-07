# TES-151 shell syntax gate correction design

## Problem

The first clean-host installation exposed a parse error in
`infra/k3s/install-control.sh`. An apostrophe inside the diagnostic word of a
`${parameter:?word}` expansion is parsed as an unmatched quote by Bash.

The repository verification command did not catch the defect because one
`bash -n` invocation with many file arguments validates only the first script;
the remaining paths become positional arguments to that script.

## Decision

Keep the correction scoped to TES-151:

- replace the contraction in the control address diagnostic with wording that
  contains no shell quote;
- make `infra/two-host/test.sh` enumerate every K3s and two-host shell script
  and invoke `bash -n` once per file;
- demonstrate that the new regression test fails before the parser correction
  and passes afterward;
- regenerate the Git bundle and both clean remote checkouts before resuming the
  installation, so host evidence always refers to the corrected commit.

This avoids adding a new linting dependency while permanently covering the
failure mode in the existing required test command.

## Rejected alternatives

- Fixing only the diagnostic would leave the verification blind spot in place.
- Adding ShellCheck or a new CI workflow would expand the issue beyond the
  minimal parser regression and require a new tool dependency.

## Verification

The correction is accepted when the test first reports the existing parse
error, then `bash infra/two-host/test.sh` validates every script and passes.
The complete TES-151 verification and clean two-host deployment are rerun from
the corrected commit.
