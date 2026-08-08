/**
 * Condensed Footer Extension
 *
 * Replaces pi's 3-row footer with a compact 1-row design (overflowing to 2 rows
 * on narrow terminals) that includes:
 *   • Session name (only if explicitly set via /session-name or pi.setSessionName())
 *   • Working directory + git branch
 *   • Token stats, cost, context usage %
 *   • Model name + thinking level
 *   • Extension statuses
 *
 * Priority on narrow terminals (drops right-to-left):
 *   1. Always kept: session + cwd + git + context %
 *   2. Model name
 *   3. Token stats + cost
 *   4. Extension statuses (first to overflow to row 2)
 *
 * Usage:
 *   /footer — toggle between condensed and default footer
 */

import type { AssistantMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

export default function (pi: ExtensionAPI) {
	let customFooterEnabled = true;
	let trackedThinkingLevel = "off";

	pi.on("thinking_level_select", async (event) => {
		trackedThinkingLevel = event.level;
	});

	function fmt(n: number): string {
		if (n < 1000) return `${n}`;
		if (n < 10_000) return `${(n / 1000).toFixed(1)}k`;
		if (n < 1_000_000) return `${Math.round(n / 1000)}k`;
		if (n < 10_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
		return `${Math.round(n / 1_000_000)}M`;
	}

	function shortenPath(path: string): string {
		const home = process.env.HOME || process.env.USERPROFILE;
		if (home && path.startsWith(home)) {
			const rest = path.slice(home.length);
			return rest ? `~${rest}` : "~";
		}
		return path;
	}

	function setCustomFooter(ctx: any) {
		if (!customFooterEnabled) return;

		ctx.ui.setFooter((tui: any, theme: any, footerData: any) => {
			const unsub = footerData.onBranchChange(() => tui.requestRender());

			return {
				dispose: unsub,
				invalidate() {},
				render(width: number): string[] {
					const sep = theme.fg("dim", " • ");

					// ── Session name (only if explicitly set) ──
					const sessionName = pi.getSessionName?.() || "";
					const sessionLabel = sessionName ? sessionName.trim() : "";

					// ── cwd + git branch ──
					const cwd: string = ctx.sessionManager.getCwd();
					let pwdLabel = shortenPath(cwd);
					const branch: string | null = footerData.getGitBranch();
					if (branch) pwdLabel = `${pwdLabel} (${branch})`;

					// ── Token stats ──
					let totalInput = 0,
						totalOutput = 0,
						totalCost = 0;
					for (const entry of ctx.sessionManager.getBranch()) {
						if (
							entry.type === "message" &&
							entry.message.role === "assistant"
						) {
							const m = entry.message as AssistantMessage;
							totalInput += m.usage.input;
							totalOutput += m.usage.output;
							totalCost += m.usage.cost.total;
						}
					}
					const statsStr = `↑${fmt(totalInput)} ↓${fmt(totalOutput)}`;

					// ── Cost ──
					const usingSubscription = ctx.model
						? ctx.modelRegistry?.isUsingOAuth(ctx.model)
						: false;
					const costStr =
						totalCost > 0 || usingSubscription
							? `$${totalCost.toFixed(3)}${usingSubscription ? " (sub)" : ""}`
							: "";

					// ── Context usage % ──
					const cu = ctx.getContextUsage();
					const windowStr = cu?.contextWindow
						? `/${fmt(cu.contextWindow)}`
						: "";
					const pct = cu?.percent != null ? cu.percent.toFixed(1) : "?";
					const pctVal = cu?.percent ?? 0;
					let contextStr: string;
					if (pctVal > 90)
						contextStr = theme.fg("error", `${pct}%${windowStr}`);
					else if (pctVal > 70)
						contextStr = theme.fg("warning", `${pct}%${windowStr}`);
					else contextStr = `${pct}%${windowStr}`;

					// ── Model + thinking ──
					const mid = ctx.model?.id || "no-model";
					const modelStr = ctx.model?.reasoning
						? trackedThinkingLevel === "off"
							? `${mid} • thinking off`
							: `${mid} • ${trackedThinkingLevel}`
						: mid;

					// ── Extension statuses ──
					const extStrs = Array.from(
						footerData.getExtensionStatuses().entries(),
					)
						.sort(([a], [b]) => a.localeCompare(b))
						.map(([, t]) => sanitize(t));

					// ── Assemble ──
					// left = [sessionName •] cwd  (session omitted if no name set)
					const leftParts = [theme.fg("dim", pwdLabel)];
					if (sessionLabel) leftParts.unshift(theme.fg("dim", sessionLabel));

					// Right items in priority order (later items overflow first)
					const rightItems: string[] = [contextStr, modelStr];
					if (statsStr) rightItems.push(theme.fg("dim", statsStr));
					if (costStr) rightItems.push(theme.fg("dim", costStr));
					for (const s of extStrs) rightItems.push(s);

					// Greedy pack onto row 1.
					// Compute total width needed: sum(visibleWidths) + sepLen * (count - 1)
					const allItems = [...leftParts, ...rightItems];
					const totalW =
						allItems.reduce((acc, it) => acc + visibleWidth(it), 0) +
						sep.length * (allItems.length - 1);

					let r1: string[];
					let r2: string[];

					if (totalW <= width) {
						// All on one row
						r1 = allItems;
						r2 = [];
					} else {
						// Greedy: keep leftParts + as many right items as fit
						r1 = [...leftParts];
						r2 = [];
						let curW =
							leftParts.reduce((acc, p) => acc + visibleWidth(p), 0) +
							sep.length * (leftParts.length - 1);

						for (const item of rightItems) {
							const itemW = visibleWidth(item);
							const wouldBe = curW + (r1.length > 0 ? sep.length : 0) + itemW;
							if (wouldBe <= width) {
								r1.push(item);
								curW = wouldBe;
							} else {
								r2.push(item);
							}
						}
					}

					const row1 = truncateToWidth(
						r1.join(sep),
						width,
						theme.fg("dim", "…"),
					);

					if (r2.length > 0) {
						const row2 = truncateToWidth(
							theme.fg("dim", r2.join(sep)),
							width,
							theme.fg("dim", "…"),
						);
						return [row1, row2];
					}

					return [row1];
				},
			};
		});
	}

	pi.on("session_start", async (_event, ctx) => {
		trackedThinkingLevel = ctx.sessionManager.getThinkingLevel?.() ?? "off";
		setCustomFooter(ctx);
	});

	pi.registerCommand("footer", {
		description:
			"Toggle condensed footer (session, cwd, stats, model in 1-2 rows)",
		handler: async (_args, ctx) => {
			customFooterEnabled = !customFooterEnabled;
			if (customFooterEnabled) {
				setCustomFooter(ctx);
				ctx.ui.notify("Condensed footer enabled", "info");
			} else {
				ctx.ui.setFooter(undefined);
				ctx.ui.notify("Default footer restored", "info");
			}
		},
	});
}

function sanitize(text: string): string {
	return text
		.replace(/[\r\n\t]/g, " ")
		.replace(/ +/g, " ")
		.trim();
}
