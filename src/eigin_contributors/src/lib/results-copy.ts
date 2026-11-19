/** Editorial text for the completed-call results page. All fields are plain text. */
export type ResultsCopy = {
  introduction: string;
  selectedSummary: string;
  runnerUpSummary: string;
  learned: string;
};
export const resultsFields = [
  {
    key: "introduction",
    example:
      "Two thoughtful approaches to safer tool use. These specs helped us see where local screening can reduce interruptions and where asking for approval still matters.",
    label: "Introduction",
    hint: "Introduce the two contributions and the direction they helped us choose.",
    limit: 1200,
  },
  {
    key: "selectedSummary",
    example:
      "A small rules-based screen checks tool responses locally and keeps approval in place whenever the result is uncertain.",
    label: "Selected spec: description",
    hint: "Describe the approach in a few sentences.",
    limit: 1200,
  },
  {
    key: "runnerUpSummary",
    example:
      "A compact multilingual classifier explores how we could screen a wider range of Danish and English tool responses on the device.",
    label: "Runner-up spec: description",
    hint: "Describe the contribution this proposal makes.",
    limit: 1200,
  },
  {
    key: "learned",
    example:
      "The strongest ideas gave uncertainty a clear place in the design. One spec offers a small, inspectable starting point; the other helps us test whether broader coverage is worth the added complexity.\n\nThank you to everyone who shared their thinking. Unselected submissions remain private.",
    label: "What we learned",
    hint: "Reflect on the call, the ideas we will carry forward, and thank the contributors.",
    limit: 6000,
  },
] as const;
export const emptyResultsCopy: ResultsCopy = {
  introduction: "",
  selectedSummary: "",
  runnerUpSummary: "",
  learned: "",
};
