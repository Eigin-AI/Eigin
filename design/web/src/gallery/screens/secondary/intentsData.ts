/** Representative stored intent content and its optional follow-up items. */
export const intents = [
  {
    content:
      "Plan a weekend in Oslo for Daniel and Sofie. Prefer the train, a small hotel and vegetarian places to eat.",
    cue: "Event in 3 weeks · 1 open task",
    tasks: [
      { content: "Compare train routes", completed: true, due: undefined },
      { content: "Shortlist places to stay", completed: false, due: "Due Friday, 23 October" },
    ],
    events: [{ content: "Weekend in Oslo", at: "6 November, 09:00" }],
    schedules: [{ content: "Check travel plans", when: "Weekly on Monday, 09:00" }],
  },
  {
    content: "Make more time for cooking.",
    cue: "Weekly on Monday, 09:00",
    tasks: [],
    events: [],
    schedules: [{ content: "Plan this week’s meals", when: "Weekly on Monday, 09:00" }],
  },
  {
    content: "Get the garden ready for spring.",
    cue: "1 open task",
    tasks: [{ content: "Choose seeds", completed: false, due: undefined }],
    events: [],
    schedules: [],
  },
];

export type GalleryIntent = (typeof intents)[number];
