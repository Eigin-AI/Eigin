/**
 * Controller tests with a fake ExtensionAPI: no pi needed. Covers the
 * behaviors the unit tests can't reach — digit assignment, digit toggling
 * (including nested close), once-per-reply feedback, number-mode enter/exit
 * rules. Run: node controller.test.ts
 */

import { registerStretchtext } from "./controller.ts";

function test(name: string, fn: () => Promise<void>): void {
	fn().then(
		() => console.log(`✓ ${name}`),
		(err) => {
			console.error(`✗ ${name}`);
			console.error(err);
			process.exitCode = 1;
		},
	);
}

function assertEqual<T>(actual: T, expected: T, message?: string): void {
	if (JSON.stringify(actual) !== JSON.stringify(expected)) {
		throw new Error(
			`${message || "Assertion failed"}\nExpected: ${JSON.stringify(expected)}\nActual: ${JSON.stringify(actual)}`,
		);
	}
}

interface FakePi {
	handlers: Map<string, Array<(event: unknown, ctx: unknown) => Promise<unknown> | unknown>>;
	transformer?: (markdown: string, context: { messageType: string; isStreaming: boolean; availableWidth: number }) => string;
	shortcuts: Map<string, { handler: (ctx: unknown) => Promise<void> | void }>;
}

function fakePi(): FakePi {
	const pi: FakePi = { handlers: new Map(), shortcuts: new Map() };
	const api = {
		on: (event: string, handler: (event: unknown, ctx: unknown) => unknown) => {
			if (!pi.handlers.has(event)) pi.handlers.set(event, []);
			pi.handlers.get(event)!.push(handler);
			return () => {};
		},
		registerMarkdownTransformer: (fn: FakePi["transformer"]) => {
			pi.transformer = fn;
		},
		registerShortcut: (key: string, opts: { handler: (ctx: unknown) => Promise<void> | void }) => {
			pi.shortcuts.set(key, opts);
		},
		registerCommand: () => {},
		appendEntry: () => {},
		getSessionName: () => "",
	};
	registerStretchtext(api as never);
	return pi;
}

function fakeCtx(branch: Array<{ type: string; message?: unknown }> = []): {
	ctx: never;
	input: (data: string) => { consume?: boolean } | undefined;
	notify: string[];
} {
	const captures = {
		notify: [] as string[],
		statuses: new Map<string, string | undefined>(),
		inputHandler: null as null | ((data: string) => { consume?: boolean } | undefined),
	};
	const ctx = {
		hasUI: true,
		ui: {
			theme: { fg: (color: string, text: string) => `<${color}>${text}</>` },
			notify: (msg: string) => captures.notify.push(msg),
			setStatus: (key: string, text: string | undefined) => captures.statuses.set(key, text),
			setHiddenThinkingLabel: () => {},
			onTerminalInput: (handler: (data: string) => { consume?: boolean } | undefined) => {
				captures.inputHandler = handler;
				return () => {};
			},
		},
		sessionManager: { getBranch: () => branch },
	} as never;
	return { ctx, input: (data) => captures.inputHandler?.(data), notify: captures.notify };
}

async function fire(pi: FakePi, event: string, payload: unknown, ctx: unknown): Promise<unknown> {
	const results: unknown[] = [];
	for (const handler of pi.handlers.get(event) ?? []) results.push(await handler(payload, ctx));
	return results[results.length - 1];
}

const render = (pi: FakePi, markdown: string) =>
	pi.transformer!(markdown, { messageType: "assistant", isStreaming: false, availableWidth: 80 });

const REPLY = "Fix landed: {{tests pass|the full test suite passes, 11 parse and 14 render cases}}.";
const NESTED = "Rule: {{always stretch|always stretch every reply {{even meta ones|this very reply, explaining its own mechanics}} when writing}}.";

test("message_end assigns digits; the transformer shows footnotes without number mode", async () => {
	const pi = fakePi();
	await fire(pi, "message_end", { message: { role: "assistant", content: [{ type: "text", text: REPLY }] } }, undefined);
	assertEqual(render(pi, REPLY).includes("¹"), true);
	assertEqual(render(pi, REPLY).includes("the full test suite"), false);
});

test("shortcut arms number mode; a digit opens and re-closes the stretch", async () => {
	const pi = fakePi();
	const { ctx, input } = fakeCtx();
	await fire(pi, "session_start", {}, ctx);
	await fire(pi, "message_end", { message: { role: "assistant", content: [{ type: "text", text: REPLY }] } }, undefined);
	await pi.shortcuts.get("ctrl+alt+e")!.handler(ctx);
	assertEqual(input("1")?.consume, true);
	const open = render(pi, REPLY);
	assertEqual(open.includes("the full test suite"), true);
	assertEqual(open.includes("«"), true);
	input("1");
	assertEqual(render(pi, REPLY).includes("the full test suite"), false);
});

test("closing a parent stretch closes nested children with it", async () => {
	const pi = fakePi();
	const { ctx, input } = fakeCtx();
	await fire(pi, "session_start", {}, ctx);
	await fire(pi, "message_end", { message: { role: "assistant", content: [{ type: "text", text: NESTED }] } }, undefined);
	await pi.shortcuts.get("ctrl+alt+e")!.handler(ctx);
	input("1"); // open the parent
	input("2"); // open the nested stretch
	assertEqual(render(pi, NESTED).includes("this very reply"), true);
	input("1"); // close the parent — child must close too
	assertEqual(render(pi, NESTED).includes("this very reply"), false);
});

test("typing a non-digit exits number mode; digits are then typed, not consumed", async () => {
	const pi = fakePi();
	const { ctx, input } = fakeCtx();
	await fire(pi, "session_start", {}, ctx);
	await fire(pi, "message_end", { message: { role: "assistant", content: [{ type: "text", text: REPLY }] } }, undefined);
	await pi.shortcuts.get("ctrl+alt+e")!.handler(ctx);
	assertEqual(input("x")?.consume ?? false, false);
	assertEqual(input("1")?.consume ?? false, false); // mode is off — digit goes to the editor
	assertEqual(render(pi, REPLY).includes("the full test suite"), false);
});

test("key releases and modifier chords don't exit number mode", async () => {
	const pi = fakePi();
	const { ctx, input } = fakeCtx();
	await fire(pi, "session_start", {}, ctx);
	await fire(pi, "message_end", { message: { role: "assistant", content: [{ type: "text", text: REPLY }] } }, undefined);
	await pi.shortcuts.get("ctrl+alt+e")!.handler(ctx);
	input("\x1b[101;1:3u"); // kitty-style key release
	assertEqual(input("1")?.consume, true); // still armed
});

test("the feedback note fires once per reply, on the next fresh user turn", async () => {
	const pi = fakePi();
	const { ctx } = fakeCtx();
	await fire(pi, "session_start", {}, ctx);
	await fire(pi, "message_end", { message: { role: "assistant", content: [{ type: "text", text: REPLY }] } }, undefined);
	const msgs = [{ role: "user", content: "next question" }];
	const event = { messages: msgs };
	const first = (await fire(pi, "context", event, ctx)) as { messages: Array<{ content: unknown }> } | undefined;
	assertEqual(first !== undefined, true);
	assertEqual(JSON.stringify(first!.messages[0].content).includes("Stretchtext:"), true);
	const second = await fire(pi, "context", event, ctx);
	assertEqual(second, undefined);
});

test("history adoption prefers the most recent reply with stretches", async () => {
	const plain = { type: "message", message: { role: "assistant", content: [{ type: "text", text: "no markup here" }] } };
	const stretchy = { type: "message", message: { role: "assistant", content: [{ type: "text", text: REPLY }] } };
	const pi = fakePi();
	const { ctx } = fakeCtx([stretchy, plain]);
	await fire(pi, "session_start", {}, ctx);
	assertEqual(render(pi, REPLY).includes("¹"), true);
});

test("the transformer ignores non-assistant markdown", async () => {
	const pi = fakePi();
	assertEqual(
		pi.transformer!("{{a|b}}", { messageType: "user", isStreaming: false, availableWidth: 80 }),
		"{{a|b}}",
	);
});

console.log("\nAll controller tests completed.");
