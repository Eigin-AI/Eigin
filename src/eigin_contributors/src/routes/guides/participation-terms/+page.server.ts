import body from "../../../../content/guides/participation-terms.md?raw";

export function load() {
  const [introduction, ...sections] = body
    .replace(/^# Participation terms\s*/, "")
    .split(/^## /m);
  return {
    introduction,
    sections: sections.map((section) => {
      const [title, ...lines] = section.split("\n");
      return {
        id: title
          .replace(/^\d+\.\s*/, "")
          .toLowerCase()
          .replace(/[^a-z0-9]+/g, "-")
          .replace(/-$/, ""),
        title,
        body: lines.join("\n").trim(),
      };
    }),
  };
}
