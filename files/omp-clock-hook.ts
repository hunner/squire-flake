import type { HookAPI } from "@oh-my-pi/pi-coding-agent/extensibility/hooks";
import { execSync } from "node:child_process";

// oh-my-pi's UserPromptSubmit equivalent: fires after the user submits a
// prompt, before the agent loop starts. Injects the current local time as
// context, same as the Claude Code / Codex UserPromptSubmit hooks in this
// flake.
export default function (pi: HookAPI): void {
	pi.on("before_agent_start", async () => {
		const now = execSync("date '+Current local time: %A %Y-%m-%d %H:%M:%S %Z'")
			.toString()
			.trim();
		return { message: { customType: "clock", content: now, display: true } };
	});
}
