import type { HookAPI } from "@oh-my-pi/pi-coding-agent/extensibility/hooks";
import { execSync } from "node:child_process";

// oh-my-pi's UserPromptSubmit equivalent (before_agent_start). Time is
// forced to Pacific regardless of the container's system timezone.
export default function (pi: HookAPI): void {
	pi.on("before_agent_start", async () => {
		const now = execSync(
			"date '+Current local time: %A %Y-%m-%d %H:%M:%S %Z'",
			{ env: { ...process.env, TZ: "America/Los_Angeles" } },
		)
			.toString()
			.trim();
		return { message: { customType: "clock", content: now, display: true } };
	});
}
