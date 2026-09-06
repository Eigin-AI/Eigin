import "@lib/generated/tokens.css";
import "@lib/generated/typography.css";
import "@lib/generated/fonts.css";
import "@gallery/app.css";

import { mount } from "svelte";
import App from "@gallery/App.svelte";

const app = mount(App, {
  target: document.getElementById("app")!,
});

export default app;
