import type { Component } from "svelte";
import Assets from "@gallery/catalog/components/Assets.svelte";
import Buttons from "@gallery/catalog/components/Buttons.svelte";
import Cards from "@gallery/catalog/components/Cards.svelte";
import Chat from "@gallery/catalog/components/Chat.svelte";
import Colors from "@gallery/catalog/fundamentals/Colors.svelte";
import Content from "@gallery/catalog/components/Content.svelte";
import Controls from "@gallery/catalog/components/Controls.svelte";
import Disclosures from "@gallery/catalog/components/Disclosures.svelte";
import Images from "@gallery/catalog/components/Images.svelte";
import Icons from "@gallery/catalog/fundamentals/Icons.svelte";
import Inputs from "@gallery/catalog/components/Inputs.svelte";
import Morph from "@gallery/catalog/components/Morph.svelte";
import Motion from "@gallery/catalog/fundamentals/Motion.svelte";
import Navigation from "@gallery/catalog/components/Navigation.svelte";
import Rows from "@gallery/catalog/components/Rows.svelte";
import Sheets from "@gallery/catalog/components/Sheets.svelte";
import Spacing from "@gallery/catalog/fundamentals/Spacing.svelte";
import Status from "@gallery/catalog/components/Status.svelte";
import Typography from "@gallery/catalog/fundamentals/Typography.svelte";

export interface CatalogEntry {
  id: string;
  title: string;
  /** Sidebar section the entry belongs to. */
  section: "fundamentals" | "components";
  /** The page itself, so this list is also the routing table. */
  component: Component;
}

export const catalogEntries: CatalogEntry[] = [
  { id: "typography", title: "Typography", section: "fundamentals", component: Typography },
  { id: "colors", title: "Colors", section: "fundamentals", component: Colors },
  { id: "icons", title: "Icons", section: "fundamentals", component: Icons },
  { id: "spacing", title: "Spacing", section: "fundamentals", component: Spacing },
  { id: "motion", title: "Motion", section: "fundamentals", component: Motion },
  { id: "buttons", title: "Buttons", section: "components", component: Buttons },
  { id: "cards", title: "Cards", section: "components", component: Cards },
  { id: "controls", title: "Controls", section: "components", component: Controls },
  { id: "inputs", title: "Inputs", section: "components", component: Inputs },
  { id: "disclosures", title: "Disclosures", section: "components", component: Disclosures },
  { id: "navigation", title: "Navigation", section: "components", component: Navigation },
  { id: "chat", title: "Chat messages", section: "components", component: Chat },
  { id: "morph", title: "Morph blob", section: "components", component: Morph },
  { id: "content", title: "Formatting", section: "components", component: Content },
  { id: "images", title: "Images", section: "components", component: Images },
  { id: "rows", title: "Content groups", section: "components", component: Rows },
  { id: "assets", title: "Assets", section: "components", component: Assets },
  { id: "sheets", title: "Sheets", section: "components", component: Sheets },
  { id: "status", title: "Status", section: "components", component: Status },
];
