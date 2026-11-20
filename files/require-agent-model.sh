# PreToolUse hook for the Agent tool: deny any call that does not name a
# model, so a subagent never inherits the parent's (expensive) model.
# Same check as the laptop's ~/.claude/settings.json hook. Fails closed:
# unreadable input also denies.
jq -e '.tool_input.model | strings | length > 0' >/dev/null && exit 0
printf '%s' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Agent call has no explicit model. Every subagent must name one so it never inherits the parent session model (Fable is expensive). Pick: opus for implementation, investigation and audits; sonnet for tests, exploring and mechanical loops; fable only for judgement-heavy writing and design deliverables."}}'
