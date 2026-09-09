/**
 * ask_questions tool — structured multi-question interview.
 *
 * Opens a tabbed dialog (1–3 questions, each with 2–3 options + free-form).
 * The agent asks clarifying questions; the user picks options (optionally
 * annotated with notes) or types free-form answers. The tool returns a
 * structured per-question summary the agent can react to in the same turn.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { askQuestions, type AskAnswer } from "./ask-dialog.ts";
import { validateQuestions, type QuestionInput } from "./validation.ts";
import { withHerdrBlocked } from "../../observability/herdr.ts";

export const ASK_QUESTIONS_TOOL = "ask_questions";

/** AFK mode auto-selects the recommended option for each question. */
export interface AskQuestionsOptions {
	isAfk(): boolean;
}

export function registerAskQuestionsTool(pi: ExtensionAPI, options: AskQuestionsOptions): void {
	const schema = Type.Object({
		questions: Type.Array(
			Type.Object({
				question: Type.String(),
				options: Type.Array(
					Type.Object({
						title: Type.String(),
						description: Type.Optional(Type.String()),
					}),
				),
			}),
		),
	});

	pi.registerTool({
		name: ASK_QUESTIONS_TOOL,
		label: "Ask Questions",
		description:
			"Ask the user 1–3 structured questions with a tabbed dialog. Each question offers 2–3 preset options " +
			"(the first option is treated as the recommended choice — put your best option first) plus an automatically " +
			"appended free-form 'Something else…' option (do NOT add your own 'other' option). The user can pick a preset " +
			"and attach a note to it, or type a free-form answer. Use this for clarifying questions or implementation decisions " +
			"during Context/Plan stages instead of plain-text back-and-forth. Returns a structured summary the agent can react " +
			"to in the same turn. Requires interactive mode.",
		promptSnippet: "Ask up to 3 structured questions with a tabbed dialog (user picks options or types answers)",
		promptGuidelines: [
			`Use ${ASK_QUESTIONS_TOOL} for clarifying questions or implementation decisions during Context/Plan, not prose Q&A.`,
			"The first option of each question is treated as recommended; put your best choice first.",
			"Each question automatically gets a free-form 'Something else…' option — do not add your own 'other' option.",
		],
		parameters: schema,
		async execute(_id, params, _signal, _onUpdate, ctx) {
			const questions = params.questions as QuestionInput[];

			// Validate counts
			const validationError = validateQuestions(questions);
			if (validationError) {
				return {
					content: [{ type: "text", text: validationError.reason }],
				};
			}

			// Non-interactive: can't prompt
			if (ctx.mode !== "tui" || !ctx.hasUI) {
				return {
					content: [
						{
							type: "text",
							text: "Cannot ask questions: no interactive UI available. Proceed without user input or note that clarification is needed.",
						},
					],
					terminate: true,
				};
			}

			// AFK: auto-pick the recommended (first) option of each question
			// without showing a dialog, so the agent keeps moving unattended.
			if (options.isAfk()) {
				const answers: AskAnswer[] = questions.map((q) => ({
					question: q.question,
					choice: { title: q.options[0].title, recommended: true },
				}));
				return {
					content: [{ type: "text", text: `AFK: auto-selected the recommended option for each question.\n\n${formatAnswers(answers)}` }],
					details: { answers },
				};
			}

			const result = await withHerdrBlocked(pi, "Answer questions", () =>
				askQuestions(ctx.ui, questions),
			);

			// Cancelled
			if (!result) {
				return {
					content: [{ type: "text", text: "User cancelled the questions." }],
					terminate: true,
				};
			}

			// Format the result for the agent
			const formatted = formatAnswers(result.answers);

			return {
				content: [{ type: "text", text: formatted }],
				details: result,
			};
		},
	});
}

function formatAnswers(answers: AskAnswer[]): string {
	const lines: string[] = ["The user answered your questions:", ""];

	for (let i = 0; i < answers.length; i++) {
		const answer = answers[i];
		lines.push(`${i + 1}. "${answer.question}"`);

		if (answer.choice) {
			const recTag = answer.choice.recommended ? " (recommended)" : "";
			lines.push(`   → Chose "${answer.choice.title}"${recTag}`);
			if (answer.choice.note) {
				lines.push(`     Note: "${answer.choice.note}"`);
			}
		} else if (answer.freeText) {
			lines.push(`   → Wrote: "${answer.freeText}"`);
		} else if (answer.noAnswer) {
			lines.push(`   → No answer given`);
		}

		lines.push("");
	}

	return lines.join("\n");
}
