/**
 * Inline multi-question dialog with tabs.
 *
 * Shows 2–3 questions, each as a tab, plus a final Submit tab. Each question
 * offers preset options (first is recommended) plus an auto-appended free-form
 * "Something else…" option. Users can pick a preset and press Tab to attach a
 * note, or choose free-form and type their own answer.
 *
 * Returns:
 *  - null                 → cancelled (Esc)
 *  - { answers }          → per-question answers
 */

import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Editor, type EditorTheme, Key, matchesKey, visibleWidth, wrapTextWithAnsi } from "@earendil-works/pi-tui";

export interface QuestionOption {
	title: string;
	description?: string;
}

export interface Question {
	question: string;
	options: QuestionOption[];
}

export interface AskAnswer {
	question: string;
	// exactly one of:
	choice?: { title: string; recommended: boolean; note?: string };
	freeText?: string;
	noAnswer?: boolean;
}

export interface AskResult {
	answers: AskAnswer[];
}

type Ui = ExtensionContext["ui"];

interface QuestionState {
	selectedIndex: number; // highlighted option (0 = recommended)
	note: string; // text attached to preset option
	freeText: string; // typed answer for "Something else…"
	confirmed: boolean; // true once the user pressed Enter to advance past this question
}

type Mode = "nav" | "note" | "freetext";

const FREEFORM_TITLE = "Something else…";

export async function askQuestions(ui: Ui, questions: Question[]): Promise<AskResult | null> {
	// Append the free-form option to each question's options
	const questionsWithFreeform = questions.map((q) => ({
		...q,
		options: [...q.options, { title: FREEFORM_TITLE }],
	}));

	return ui.custom<AskResult | null>((tui, theme, _kb, done) => {
		const numQuestions = questionsWithFreeform.length;
		const submitTabIndex = numQuestions;

		let tabIndex = 0; // 0..numQuestions-1 = questions, numQuestions = Submit
		let mode: Mode = "nav";
		let cachedLines: string[] | undefined;

		// Per-question state
		const questionStates: QuestionState[] = questionsWithFreeform.map(() => ({
			selectedIndex: 0, // recommended is first
			note: "",
			freeText: "",
			confirmed: false,
		}));

		const editorTheme: EditorTheme = {
			borderColor: (s) => theme.fg("accent", s),
			selectList: {
				selectedPrefix: (t) => theme.fg("accent", t),
				selectedText: (t) => theme.fg("accent", t),
				description: (t) => theme.fg("muted", t),
				scrollInfo: (t) => theme.fg("dim", t),
				noMatch: (t) => theme.fg("warning", t),
			},
		};
		const editor = new Editor(tui, editorTheme);

		editor.onSubmit = (text) => {
			const state = currentQuestionState();
			if (!state) return;

			// Editor.submitValue() clears its internal state before invoking this
			// callback, so the submitted text must be read from the `text` param —
			// editor.getText() would return empty at this point.
			if (mode === "note") {
				state.note = text.trim();
				mode = "nav";
			} else if (mode === "freetext") {
				state.freeText = text.trim();
				mode = "nav";
			}
			refresh();
		};

		function currentQuestionState(): QuestionState | undefined {
			return tabIndex < numQuestions ? questionStates[tabIndex] : undefined;
		}

		function refresh(): void {
			cachedLines = undefined;
			tui.requestRender();
		}

		function buildResult(): AskResult {
			const answers: AskAnswer[] = [];

			for (let i = 0; i < numQuestions; i++) {
				const q = questionsWithFreeform[i];
				const state = questionStates[i];
				const selectedOption = q.options[state.selectedIndex];
				const isFreeform = state.selectedIndex === q.options.length - 1;

				if (isFreeform) {
					if (state.freeText) {
						answers.push({ question: q.question, freeText: state.freeText });
					} else {
						answers.push({ question: q.question, noAnswer: true });
					}
				} else {
					const answer: AskAnswer = {
						question: q.question,
						choice: {
							title: selectedOption.title,
							recommended: state.selectedIndex === 0,
							note: state.note || undefined,
						},
					};
					answers.push(answer);
				}
			}

			return { answers };
		}

		function handleInput(data: string): void {
			const state = currentQuestionState();

			// Edit modes
			if (mode === "note" || mode === "freetext") {
				if (matchesKey(data, Key.escape)) {
					// Discard in-progress edit
					mode = "nav";
					editor.setText("");
					refresh();
					return;
				}
				editor.handleInput(data);
				refresh();
				return;
			}

			// Nav mode
			if (matchesKey(data, Key.up)) {
				if (state) {
					state.selectedIndex = Math.max(0, state.selectedIndex - 1);
					refresh();
				}
				return;
			}
			if (matchesKey(data, Key.down)) {
				if (state) {
					const maxIndex = questionsWithFreeform[tabIndex].options.length - 1;
					state.selectedIndex = Math.min(maxIndex, state.selectedIndex + 1);
					refresh();
				}
				return;
			}
			if (matchesKey(data, Key.left)) {
				tabIndex = Math.max(0, tabIndex - 1);
				refresh();
				return;
			}
			if (matchesKey(data, Key.right)) {
				tabIndex = Math.min(submitTabIndex, tabIndex + 1);
				refresh();
				return;
			}
			if (matchesKey(data, Key.tab)) {
				if (state) {
					const isFreeform = state.selectedIndex === questionsWithFreeform[tabIndex].options.length - 1;
					if (isFreeform) {
						// Enter free-text mode
						mode = "freetext";
						editor.setText(state.freeText);
					} else {
						// Enter note mode
						mode = "note";
						editor.setText(state.note);
					}
					refresh();
				}
				return;
			}
			if (matchesKey(data, Key.enter)) {
				if (tabIndex === submitTabIndex) {
					// Submit
					done(buildResult());
					return;
				}
				// On a question tab: advance (or also enter freetext if on freeform option)
				if (state) {
					const isFreeform = state.selectedIndex === questionsWithFreeform[tabIndex].options.length - 1;
					if (isFreeform && !state.freeText) {
						// Enter freetext editor on Enter when freeform is selected and empty
						mode = "freetext";
						editor.setText(state.freeText);
						refresh();
						return;
					}

					state.confirmed = true;
					tabIndex = Math.min(submitTabIndex, tabIndex + 1);
					refresh();
				}
				return;
			}
			if (matchesKey(data, Key.escape)) {
				done(null);
			}
		}

		function render(width: number): string[] {
			if (cachedLines) return cachedLines;

			const lines: string[] = [];
			const renderWidth = Math.max(1, width);

			function addWrappedWithPrefix(prefix: string, text: string): void {
				const prefixWidth = visibleWidth(prefix);
				if (prefixWidth >= renderWidth) {
					lines.push(...wrapTextWithAnsi(prefix + text, renderWidth));
					return;
				}
				const wrapped = wrapTextWithAnsi(text, renderWidth - prefixWidth);
				const continuation = " ".repeat(prefixWidth);
				for (let i = 0; i < wrapped.length; i++) {
					lines.push(`${i === 0 ? prefix : continuation}${wrapped[i]}`);
				}
			}

			lines.push(theme.fg("accent", "─".repeat(renderWidth)));

			// Tab bar: "1 · 2✓ · 3 · Submit" (checkmark once a question has an active answer)
			const tabLabels: string[] = [];
			for (let i = 0; i < numQuestions; i++) {
				const label = `${i + 1}${questionStates[i].confirmed ? "✓" : ""}`;
				tabLabels.push(i === tabIndex ? theme.fg("accent", label) : theme.fg("muted", label));
			}
			tabLabels.push(
				tabIndex === submitTabIndex ? theme.fg("accent", "Submit") : theme.fg("muted", "Submit"),
			);
			addWrappedWithPrefix(" ", tabLabels.join(theme.fg("dim", " · ")));
			lines.push("");

			if (tabIndex === submitTabIndex) {
				// Submit tab: show review
				addWrappedWithPrefix(" ", theme.fg("text", theme.bold("Review your answers")));
				lines.push("");

				for (let i = 0; i < numQuestions; i++) {
					const q = questionsWithFreeform[i];
					const state = questionStates[i];
					const isFreeform = state.selectedIndex === q.options.length - 1;

					addWrappedWithPrefix(` ${i + 1}. `, theme.fg("text", q.question));

					if (isFreeform) {
						if (state.freeText) {
							addWrappedWithPrefix("    → ", theme.fg("text", `Wrote: "${state.freeText}"`));
						} else {
							addWrappedWithPrefix("    → ", theme.fg("muted", "No answer given"));
						}
					} else {
						const option = q.options[state.selectedIndex];
						const recTag = state.selectedIndex === 0 ? " (recommended)" : "";
						addWrappedWithPrefix("    → ", theme.fg("text", `Chose "${option.title}"${recTag}`));
						if (state.note) {
							addWrappedWithPrefix("      ", theme.fg("muted", `Note: "${state.note}"`));
						}
					}
					lines.push("");
				}
			} else {
				// Question tab
				const q = questionsWithFreeform[tabIndex];
				const state = questionStates[tabIndex];

				addWrappedWithPrefix(" ", theme.fg("text", theme.bold(q.question)));
				lines.push("");

				for (let i = 0; i < q.options.length; i++) {
					const opt = q.options[i];
					const selected = i === state.selectedIndex;
					const isRecommended = i === 0 && opt.title !== FREEFORM_TITLE;
					const isFreeform = opt.title === FREEFORM_TITLE;

					const prefix = selected ? theme.fg("accent", "> ") : "  ";
					const titleTag = isRecommended ? ` ${theme.fg("muted", "(recommended)")}` : "";
					const titleText = theme.fg(selected ? "accent" : "text", opt.title) + titleTag;

					addWrappedWithPrefix(prefix, titleText);

					if (opt.description) {
						addWrappedWithPrefix("  ", theme.fg("muted", opt.description));
					}

					if (isFreeform && state.freeText) {
						addWrappedWithPrefix("  ", theme.fg("muted", `"${state.freeText}"`));
					}

					// Show the attached note directly under the option it belongs to,
					// not just on the Submit review.
					if (!isFreeform && selected && state.note) {
						addWrappedWithPrefix("  ", theme.fg("muted", `Note: "${state.note}"`));
					}
				}

				// Editor block for note/freetext
				if (mode === "note") {
					lines.push("");
					const selectedOption = q.options[state.selectedIndex];
					addWrappedWithPrefix(" ", theme.fg("muted", `Note (attached to "${selectedOption.title}"):`));
					for (const line of editor.render(Math.max(1, renderWidth - 2))) {
						lines.push(` ${line}`);
					}
				} else if (mode === "freetext") {
					lines.push("");
					addWrappedWithPrefix(" ", theme.fg("muted", "Your answer:"));
					for (const line of editor.render(Math.max(1, renderWidth - 2))) {
						lines.push(` ${line}`);
					}
				}
			}

			lines.push("");

			// Help line
			let help: string;
			if (mode === "note" || mode === "freetext") {
				help = "Enter to save • Esc to discard";
			} else if (tabIndex === submitTabIndex) {
				help = "←→ tabs • Enter submit • Esc cancel";
			} else {
				help = "↑↓ choose • ←→ tabs • Tab note • Enter next • Esc cancel";
			}
			addWrappedWithPrefix(" ", theme.fg("dim", help));

			lines.push(theme.fg("accent", "─".repeat(renderWidth)));

			cachedLines = lines;
			return lines;
		}

		return {
			render,
			invalidate: () => {
				cachedLines = undefined;
			},
			handleInput,
		};
	});
}
