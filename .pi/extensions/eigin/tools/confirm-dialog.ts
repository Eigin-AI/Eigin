/**
 * Inline confirm-with-note dialog.
 *
 * A yes/no confirmation where the user can press Tab to attach a free-text
 * note inline (no second step). The note travels back with the decision, so
 * the user can say "no, because…" or "yes, but first…" and have the agent
 * react to it.
 *
 * Returns:
 *  - null                       → cancelled (Esc)
 *  - { confirmed, note? }       → Yes/No, with an optional note
 */

import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import {
  Editor,
  type EditorTheme,
  Key,
  matchesKey,
  visibleWidth,
  wrapTextWithAnsi,
} from "@earendil-works/pi-tui";

export interface ConfirmWithNoteResult {
  confirmed: boolean;
  note?: string;
}

type Ui = ExtensionContext["ui"];

export async function confirmWithNote(
  ui: Ui,
  title: string,
  detail: string,
): Promise<ConfirmWithNoteResult | null> {
  const options = ["Yes", "No"];

  return ui.custom<ConfirmWithNoteResult | null>((tui, theme, _kb, done) => {
    let optionIndex = 0;
    let editMode = false;
    let cachedLines: string[] | undefined;

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

    editor.onSubmit = (value) => {
      const note = value.trim();
      done({
        confirmed: optionIndex === 0,
        note: note.length > 0 ? note : undefined,
      });
    };

    function refresh(): void {
      cachedLines = undefined;
      tui.requestRender();
    }

    function handleInput(data: string): void {
      if (editMode) {
        if (matchesKey(data, Key.escape)) {
          editMode = false;
          editor.setText("");
          refresh();
          return;
        }
        editor.handleInput(data);
        refresh();
        return;
      }

      if (matchesKey(data, Key.up) || matchesKey(data, Key.left)) {
        optionIndex = Math.max(0, optionIndex - 1);
        refresh();
        return;
      }
      if (matchesKey(data, Key.down) || matchesKey(data, Key.right)) {
        optionIndex = Math.min(options.length - 1, optionIndex + 1);
        refresh();
        return;
      }
      if (matchesKey(data, Key.tab)) {
        editMode = true;
        refresh();
        return;
      }
      if (matchesKey(data, Key.enter)) {
        done({ confirmed: optionIndex === 0 });
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
      addWrappedWithPrefix(" ", theme.fg("text", theme.bold(title)));
      addWrappedWithPrefix(" ", theme.fg("muted", detail));
      lines.push("");

      for (let i = 0; i < options.length; i++) {
        const selected = i === optionIndex;
        const prefix = selected ? theme.fg("accent", "> ") : "  ";
        addWrappedWithPrefix(
          prefix,
          theme.fg(selected ? "accent" : "text", options[i]),
        );
      }

      if (editMode) {
        lines.push("");
        addWrappedWithPrefix(
          " ",
          theme.fg("muted", `Note (attached to "${options[optionIndex]}"):`),
        );
        for (const line of editor.render(Math.max(1, renderWidth - 2))) {
          lines.push(` ${line}`);
        }
      }

      lines.push("");
      addWrappedWithPrefix(
        " ",
        theme.fg(
          "dim",
          editMode
            ? "Enter to submit • Esc to drop the note"
            : "↑↓ choose • Tab to add a note • Enter to confirm • Esc to cancel",
        ),
      );
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
