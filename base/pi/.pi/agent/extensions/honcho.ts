import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "@sinclair/typebox";

const DEFAULT_URL = "http://datacore.scottwhitson.ts.net:8008";
const DEFAULT_WORKSPACE = "pi";

async function apiPost(endpoint: string, body: unknown): Promise<Response> {
	const url = process.env.HONCHO_URL ?? DEFAULT_URL;
	return fetch(`${url}${endpoint}`, {
		method: "POST",
		headers: { "Content-Type": "application/json" },
		body: JSON.stringify(body),
	});
}

async function apiPut(endpoint: string, body: unknown): Promise<Response> {
	const url = process.env.HONCHO_URL ?? DEFAULT_URL;
	return fetch(`${url}${endpoint}`, {
		method: "PUT",
		headers: { "Content-Type": "application/json" },
		body: JSON.stringify(body),
	});
}

function workspace(path: string): string {
	const ws = process.env.HONCHO_WORKSPACE ?? DEFAULT_WORKSPACE;
	return `/v3/workspaces/${ws}${path}`;
}

export default function (pi: ExtensionAPI) {
	// ─── Query tool (existing) ───────────────────────────────────────

	pi.registerTool({
		name: "honcho_query",
		label: "Honcho Query",
		description:
			"Query canonical Honcho for personalized memory before answering when useful.",
		parameters: Type.Object({
			query: Type.String({ description: "Question to ask Honcho" }),
			reasoning_level: Type.Optional(
				Type.Union([
					Type.Literal("minimal"),
					Type.Literal("low"),
					Type.Literal("medium"),
					Type.Literal("high"),
					Type.Literal("max"),
				]),
			),
			target_peer: Type.Optional(
				Type.String({ description: "Peer to query from the perspective of" }),
			),
			session_id: Type.Optional(
				Type.String({ description: "Session ID to scope the query" }),
			),
		}) as any,
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			const assistantPeer =
				process.env.HONCHO_ASSISTANT_PEER ?? "honcho-assistant";
			const targetPeer =
				(params as any).target_peer ??
				process.env.HONCHO_USER_PEER ??
				ctx.cwd.split("/").pop() ??
				"arch-user";
			const response = await apiPost(
				workspace(`/peers/${assistantPeer}/chat`),
				{
					query: (params as any).query,
					session_id: (params as any).session_id ?? null,
					target: targetPeer,
					reasoning_level: (params as any).reasoning_level ?? "low",
				},
			);
			const text = await response.text();
			if (!response.ok) {
				return {
					content: [
						{
							type: "text",
							text: `Honcho query failed (${response.status}): ${text}`,
						},
					],
					details: { ok: false, status: response.status },
				};
			}
			return {
				content: [{ type: "text", text }],
				details: { ok: true },
			};
		},
	});

	// ─── Remember tool — write a durable conclusion ──────────────────

	pi.registerTool({
		name: "honcho_remember",
		label: "Honcho Remember",
		description:
			"Store a durable fact about a peer in Honcho. Use for preferences, decisions, and other curated facts that should persist across sessions.",
		parameters: Type.Object({
			fact: Type.String({
				description: "Durable fact to remember about the peer",
			}),
			observed_peer: Type.Optional(
				Type.String({
					description:
						"Peer to remember about. Defaults to the current user peer (scott).",
				}),
			),
			observer_peer: Type.Optional(
				Type.String({
					description:
						"Perspective peer. Defaults to the assistant peer (honcho-assistant).",
				}),
			),
			session_id: Type.Optional(
				Type.String({
					description:
						"Optional session ID to associate with the fact. Created if needed.",
				}),
			),
		}) as any,
		async execute(_toolCallId, params, _signal, _onUpdate, _ctx) {
			const assistantPeer =
				process.env.HONCHO_ASSISTANT_PEER ?? "honcho-assistant";
			const observedPeer =
				(params as any).observed_peer ??
				process.env.HONCHO_USER_PEER ??
				"arch-user";
			const observerPeer = (params as any).observer_peer ?? assistantPeer;
			const sessionId = (params as any).session_id ?? "pi-memory-facts";

			// Ensure session exists
			await apiPost(workspace("/sessions"), { id: sessionId }).catch(() => {});

			// Create conclusion
			const response = await apiPost(workspace("/conclusions"), {
				conclusions: [
					{
						content: (params as any).fact,
						observer_id: observerPeer,
						observed_id: observedPeer,
						session_id: sessionId,
					},
				],
			});
			const text = await response.text();
			if (!response.ok) {
				return {
					content: [
						{
							type: "text",
							text: `Honcho remember failed (${response.status}): ${text}`,
						},
					],
					details: { ok: false, status: response.status },
				};
			}
			return {
				content: [
					{
						type: "text",
						text: `Remembered: ${(params as any).fact}`,
					},
				],
				details: { ok: true },
			};
		},
	});

	// ─── Set peer card tool — stable profile facts ───────────────────

	pi.registerTool({
		name: "honcho_set_card",
		label: "Honcho Set Peer Card",
		description:
			"Set stable biographical facts about a peer (preferences, instructions, profile). Replaces entire card. Max 40 facts.",
		parameters: Type.Object({
			facts: Type.Array(Type.String(), {
				description: "List of stable profile facts",
			}),
			peer_id: Type.Optional(
				Type.String({
					description:
						"Peer to update. Defaults to current user peer (arch-user).",
				}),
			),
		}) as any,
		async execute(_toolCallId, params, _signal, _onUpdate, _ctx) {
			const peerId =
				(params as any).peer_id ?? process.env.HONCHO_USER_PEER ?? "arch-user";
			const response = await apiPut(workspace(`/peers/${peerId}/card`), {
				peer_card: (params as any).facts,
			});
			const text = await response.text();
			if (!response.ok) {
				return {
					content: [
						{
							type: "text",
							text: `Honcho set card failed (${response.status}): ${text}`,
						},
					],
					details: { ok: false, status: response.status },
				};
			}
			return {
				content: [
					{
						type: "text",
						text: `Peer card updated for ${peerId}: ${(params as any).facts.join(", ")}`,
					},
				],
				details: { ok: true },
			};
		},
	});

	// ─── Write turns tool — conversation turns to session messages ──

	pi.registerTool({
		name: "honcho_write_turns",
		label: "Honcho Write Turns",
		description:
			"Write conversation turns to a Honcho session for background reasoning. Use for every user-assistant exchange.",
		parameters: Type.Object({
			messages: Type.Array(
				Type.Object({
					peer_id: Type.String({ description: "Peer ID sending the message" }),
					content: Type.String({ description: "Message text" }),
				}),
				{ description: "Messages to store (max 100)" },
			),
			session_id: Type.Optional(
				Type.String({
					description:
						"Session ID. Created if needed. Defaults to pi-agent-YYYY-MM-DD.",
				}),
			),
		}) as any,
		async execute(_toolCallId, params, _signal, _onUpdate, _ctx) {
			const today = new Date().toISOString().slice(0, 10);
			const sessionId = (params as any).session_id ?? `pi-agent-${today}`;

			// Ensure session exists
			await apiPost(workspace("/sessions"), { id: sessionId }).catch(() => {});

			const response = await apiPost(
				workspace(`/sessions/${sessionId}/messages`),
				{ messages: (params as any).messages },
			);
			const text = await response.text();
			if (!response.ok) {
				return {
					content: [
						{
							type: "text",
							text: `Honcho write turns failed (${response.status}): ${text}`,
						},
					],
					details: {
						ok: false,
						status: response.status,
						session_id: sessionId,
					},
				};
			}
			return {
				content: [
					{
						type: "text",
						text: `Recorded ${(params as any).messages.length} messages to session ${sessionId}`,
					},
				],
				details: { ok: true, session_id: sessionId },
			};
		},
	});

	// ─── Before-answer hook (existing) ───────────────────────────────

	pi.on("before_agent_start", async (event, ctx) => {
		const queryMode = process.env.HONCHO_QUERY_MODE ?? "before_answer";
		if (queryMode !== "before_answer") return;
		const enabled = (process.env.HONCHO_ENABLED ?? "true") === "true";
		if (!enabled) return;

		const assistantPeer =
			process.env.HONCHO_ASSISTANT_PEER ?? "honcho-assistant";
		const userPeer = process.env.HONCHO_USER_PEER ?? "arch-user";
		const prompt = event.prompt?.trim();
		if (!prompt) return;

		try {
			const response = await apiPost(
				workspace(`/peers/${assistantPeer}/chat`),
				{
					query: `What relevant durable context should the assistant know before answering: ${prompt}`,
					session_id: null,
					target: userPeer,
					reasoning_level: "minimal",
				},
			);
			if (!response.ok) return;
			const data = (await response.json()) as { content?: string };
			if (!data.content) return;
			return {
				systemPrompt: `${event.systemPrompt}\n\nHONCHO CONTEXT:\n${data.content}\n\nPolicy: query before answer when personalized memory helps; write only curated durable facts, decisions, and preferences.`,
			};
		} catch {
			return;
		}
	});
}
