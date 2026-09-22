---
name: judging-refactor-worth
description: Decide whether a code-quality or latent-bug finding in mcp-axiomatic is worth fixing now, later, or never, and record the verdict in the personal debt ledger instead of a ticket. Invoke when an agent or reviewer surfaces a refactor, cleanup, drift, or latent-bug finding that the current task does not require.

harness: claude

model: anthropic/claude-fable-5-1
---

You are pricing effort against value, not deciding right against wrong. A
finding can be correct and still not be worth doing. A bug goes through the
same gate as a style nit: being a bug raises the harm side, it does not skip
the cost side.

## Input

A finding must carry `where` (file:line), `claim` (one sentence), `fix` (one
sentence), and whatever evidence the finder has. If it lacks `where` or `fix`,
send it back. You cannot price a fix nobody has described.

## Gather before judging

All five are cheap. The first three are mandatory; no verdict without them.

1. **Failure story.** An incident, failing test, or reproduction. Check
   `git log -S` on the code and `docs/impl-authoring-gotchas.md`. "None" is a
   valid answer and must be written down.
2. **Touch count.** `grep -rn` the symbol. Files and call sites the fix changes.
3. **Contract surface.** Does the fix change generated YAML, error text, CLI
   flags or output, or anything a test asserts? Name the tests.
4. **Reachability.** For concurrency or shared-state findings: which command
   runs the path, with what parallelism (`--workers` defaults).
5. **Where the code lives.** On an unmerged PR, changing it is a review comment
   and costs nearly nothing. On main, it is a change someone must review.

## Verdicts

- **FOLD IN**: fix inside the PR you are already in. Requires the code to be on
  this PR, or the fix to touch only files this PR already changes, plus at most
  two files touched and no contract change beyond the one being fixed.
- **OWN PR**: worth doing now, as a separate PR with its own test. Requires a
  failure story or a demonstrated bug (a failing `go test -race` counts) and a
  fix that stays inside one package.
- **QUEUE**: worth doing when the code is next touched for another reason.
  Record the trigger. For consistency findings, record the convention chosen.
- **DROP**: not worth doing. Record why once so the next agent does not
  re-surface it.

Harm ranking, highest first: silent output corruption, then re-parse or
runtime failure, then cross-impl contamination, then reader confusion, then
taste. Something in the bottom two tiers is never OWN PR.

## What makes a refactor unwise

- No failure story and more than two files touched. That is churn with a
  review cost and nothing to justify the reviewer's attention.
- It changes a contract (YAML shape, error text, flags) for consistency alone.
  Users and tests pin those; the reader does not.
- It picks one of two undocumented conventions. Decide the convention first, in
  one line in the ledger or `docs/invariants.md`. Change code only when the
  file is next open.
- It adds an abstraction for a second caller that does not exist yet.
- It threads state through a call chain when a return value or a per-run
  struct inside one file would do. Take the narrowest fix that removes the bug.
- It touches code nobody understands without first adding a test that pins
  current behavior. Low institutional knowledge cuts both ways: there is no
  intent to violate, so precedent is not a reason to leave code that takes
  three steps to read; there is also no safety net, so the test is it.
- It rides along in an unrelated PR outside the FOLD IN rule. Mixed PRs get
  worse reviews and harder reverts.

## Output: the ledger, not a ticket

Append one entry per finding to the personal ledger. In a Squire env that is
the arena file `/debt/mcp-axiomatic.md`, which outlives the env. Elsewhere it
is `~/.mcp-axiomatic-debt.md`. Never commit it, never open a Linear issue,
never post it to a channel.

Why a ledger: a ticket is a commitment someone else must triage. A repo doc is
a commit that needs review and goes stale. The ledger costs nothing to ignore
and has one owner. Promoting an entry to a ticket or a PR is a human act.

Entry format, newest last. FOLD IN and OWN PR get entries too, so the ledger
also records what was fixed and why.

    ## 2026-09-21 QUEUE internal/gen/validate.go:640 mixed error addressing in validateMCPPrompts
    harm: reader confusion, none observed · cost: 4 strings + tests · touch: 1 file · contract: error text
    trigger: next edit of this validator · convention: index before the name is validated, name after

## Calibration (repo state as of 2026-09-21)

1. `toMCPResource` and `toMCPResourceTemplate` in `internal/gen/mcp.go` copy
   `Description` untrimmed while `toMCPTool` trims. Failure story: an indented
   first line made the YAML emitter pick a block-scalar indicator later lines
   violated, and monday.com `create_automation` failed to re-parse. Touch: two
   lines, one file; the output change is the fix. **FOLD IN** to any PR touching
   that file, else **OWN PR**. `toMCPPrompt` on PR #624 has the same gap and is
   a review comment.
2. `validateMCPPrompts` on PR #624 mixes `mcp_prompts[%d]` with
   `mcp_prompts[%s]`. No failure story; the contract is error text. On the PR:
   **FOLD IN**, new code is free to change. The same finding on main, with tests
   asserting the strings: **QUEUE** with the convention recorded.
3. `unmatchedGetOps` is a package-level var in `internal/gen/openapi.go`,
   assigned, appended, and consumed at three sites in that one file.
   `mcp-gen batch` runs `GenerateImpl` across `--workers` goroutines, default
   10. Silent cross-impl contamination, top of the harm ranking. Every
   reference is in one file, so a return value or per-run struct fixes it
   without threading state through the chain. **OWN PR**, with a `-race` test
   that fails first.

None of the three is DROP. DROP is for a finding with no failure story, a real
contract change, and no cheap trigger. The ledger is where those are recorded
once and left alone.
