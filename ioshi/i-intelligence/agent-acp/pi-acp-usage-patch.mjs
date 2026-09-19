#!/usr/bin/env node
/**
 * Add ACP usage_update notifications to the imperative pi-acp payload.
 *
 * pi-acp keeps the authoritative cumulative cost in pi's RPC session stats,
 * but older releases do not bridge that value into ACP. agent-shell already
 * understands usage_update, so this small post-install patch keeps the
 * adapter wrapper imperative without duplicating the RPC client.
 */

import { readFileSync, writeFileSync } from "node:fs";

const path = process.argv[2];
if (!path) throw new Error("usage: pi-acp-usage-patch.mjs <dist/index.js>");

let source = readFileSync(path, "utf8");
const methodMarker = "  startTurn(t) {";
const usageMethod = `  async emitUsageUpdate() {
    try {
      const stats = await this.proc.getSessionStats();
      const update = { sessionUpdate: "usage_update" };
      const context = stats?.contextUsage;
      if (typeof context?.tokens === "number") update.used = context.tokens;
      if (typeof context?.contextWindow === "number") update.size = context.contextWindow;
      if (typeof stats?.cost === "number") {
        update.cost = { amount: stats.cost, currency: "USD" };
      }
      if (Object.keys(update).length > 1) this.emit(update);
    } catch {
      // Usage is optional telemetry; never make a completed turn fail.
    }
  }
`;

if (!source.includes("async emitUsageUpdate()")) {
	if (!source.includes(methodMarker)) {
		throw new Error("pi-acp-usage-patch: startTurn anchor not found");
	}
	source = source.replace(methodMarker, usageMethod + methodMarker);
}

const settledMarker = `case "agent_settled": {
        void this.flushEmits().finally(() => {`;
const settledReplacement = `case "agent_settled": {
        void this.emitUsageUpdate().finally(() => this.flushEmits()).finally(() => {`;

if (!source.includes("this.emitUsageUpdate().finally")) {
	if (!source.includes(settledMarker)) {
		throw new Error("pi-acp-usage-patch: agent_settled anchor not found");
	}
	source = source.replace(settledMarker, settledReplacement);
}

writeFileSync(path, source);
