/**
 * Pure validation functions for ask_questions tool schema.
 */

export interface QuestionInput {
  question: string;
  options: Array<{ title: string; description?: string }>;
}

export interface ValidationError {
  reason: string;
}

const MIN_QUESTIONS = 1;
const MAX_QUESTIONS = 3;
const MIN_OPTIONS = 2;
const MAX_OPTIONS = 3;

/**
 * Validate that questions and options arrays are within allowed ranges.
 * Returns an error if validation fails, undefined if valid.
 */
export function validateQuestions(
  questions: QuestionInput[],
): ValidationError | undefined {
  // Check question count
  if (questions.length < MIN_QUESTIONS || questions.length > MAX_QUESTIONS) {
    return {
      reason: `ask_questions requires ${MIN_QUESTIONS}–${MAX_QUESTIONS} questions; got ${questions.length}. Please adjust and try again.`,
    };
  }

  // Check each question
  for (let i = 0; i < questions.length; i++) {
    const q = questions[i];

    // Empty question text
    if (!q.question.trim()) {
      return {
        reason: `Question ${i + 1} has empty text. Each question must have descriptive text.`,
      };
    }

    // Check option count
    if (q.options.length < MIN_OPTIONS || q.options.length > MAX_OPTIONS) {
      return {
        reason: `Question ${i + 1} ("${q.question}") has ${q.options.length} options; need ${MIN_OPTIONS}–${MAX_OPTIONS}. A question with only one option is not a real question.`,
      };
    }

    // Check option titles
    for (let j = 0; j < q.options.length; j++) {
      if (!q.options[j].title.trim()) {
        return {
          reason: `Question ${i + 1} ("${q.question}"), option ${j + 1}: title is empty. Each option must have a title.`,
        };
      }
    }
  }

  return undefined;
}
