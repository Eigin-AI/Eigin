import type { Component } from "svelte";
import AddIntegrationScreen from "@gallery/screens/AddIntegrationScreen.svelte";
import ConnectIntegrationScreen from "@gallery/screens/ConnectIntegrationScreen.svelte";
import AiProviderScreen from "@gallery/screens/AiProviderScreen.svelte";
import ProviderModelsScreen from "@gallery/screens/ProviderModelsScreen.svelte";
import AgentScreen from "@gallery/screens/AgentScreen.svelte";
import CallScreen from "@gallery/screens/CallScreen.svelte";
import ChatListScreen from "@gallery/screens/ChatListScreen.svelte";
import ChatScreen from "@gallery/screens/ChatScreen.svelte";
import ConnectionsScreen from "@gallery/screens/ConnectionsScreen.svelte";
import EiginProviderScreen from "@gallery/screens/EiginProviderScreen.svelte";
import GetCreditsScreen from "@gallery/screens/GetCreditsScreen.svelte";
import IntegrationScreen from "@gallery/screens/IntegrationScreen.svelte";
import OffersScreen from "@gallery/screens/OffersScreen.svelte";
import LocalModelInfoScreen from "@gallery/screens/LocalModelInfoScreen.svelte";
import LocalModelScreen from "@gallery/screens/LocalModelScreen.svelte";
import RelayInfoScreen from "@gallery/screens/RelayInfoScreen.svelte";
import ProviderConnectScreen from "@gallery/screens/ProviderConnectScreen.svelte";
import ProviderSelectScreen from "@gallery/screens/ProviderSelectScreen.svelte";
import SettingsScreen from "@gallery/screens/SettingsScreen.svelte";
import WatchScreen from "@gallery/screens/WatchScreen.svelte";

export interface ScreenEntry {
  id: string;
  title: string;
  /** Which sidebar group the screen folds into. */
  section: string;
  /** The screen itself, so this list is also the routing table. */
  component: Component;
  /** What this screen is for, in a sentence or two, shown under the phone. */
  about?: string;
  /**
   * The device this screen runs on. A screen belongs to one form factor —
   * the watch companion is not a small iPhone — so the stage offers only
   * that device rather than every frame the gallery can draw.
   */
  device?: string;
}

/**
 * Sidebar groups, in order. A group with no screens is not drawn, so a new
 * area of the app costs one entry here and one per screen below.
 *
 * The app has four screens you can reach from the tab bar and a long tail of
 * everything behind them, so the tail is grouped by the area it belongs to
 * rather than piled into one list. Only the group you are in stays unfolded.
 */
export const screenSections: { id: string; title: string }[] = [
  { id: "primary", title: "Main screens" },
  { id: "connections", title: "Connections" },
  { id: "watch", title: "Watch" },
];

/**
 * Every screen the gallery can show.
 *
 * A sheet is a screen here: it gets its own entry and renders over whichever
 * screen opens it, because that is the only way to see it in place.
 */
export const screenEntries: ScreenEntry[] = [
  {
    id: "chat-list",
    title: "Chat list",
    section: "primary",
    component: ChatListScreen,
    about: "Every conversation, most recent first.",
  },
  {
    id: "chat",
    title: "Chat",
    section: "primary",
    component: ChatScreen,
    about: "One conversation, with the agent's tools and thinking shown as it works.",
  },
  {
    id: "call",
    title: "Call",
    section: "primary",
    component: CallScreen,
    about: "A spoken conversation, hands free.",
  },
  {
    id: "agent",
    title: "Agent",
    section: "primary",
    component: AgentScreen,
    about: "Who the agent is and what it can reach: identity, soul, skills and models.",
  },
  {
    id: "settings",
    title: "Settings",
    section: "primary",
    component: SettingsScreen,
    about: "Everything about the app itself, and the way through to connections.",
  },

  {
    id: "connections",
    title: "Connections hub",
    section: "connections",
    component: ConnectionsScreen,
    about:
      "Every connection in one place: the models Eigin thinks with, and the services it can reach for you. Whatever is behind a connection, it is listed the same way, so the question is what you are using rather than how it is wired. Adding starts here, and anything that needs you says so.",
  },
  {
    id: "eigin-provider",
    title: "Eigin Relay",
    section: "connections",
    component: EiginProviderScreen,
    about:
      "Inspect the chat credit balance, understand what the relay is and why it is private, and top up when it runs low. Says plainly when credits are short or the service is down.",
  },
  {
    id: "get-credits",
    title: "Eigin Relay · Get credits",
    section: "connections",
    component: GetCreditsScreen,
    about:
      "Buy a pack of credits, or restore an earlier purchase. The small print about payments and third-party processing sits at the foot, before you commit.",
  },
  {
    id: "relay-info",
    title: "Eigin Relay · How it works",
    section: "connections",
    component: RelayInfoScreen,
    about:
      "What the relay is, in plain language: where it runs, what it keeps, and what a credit buys.",
  },
  {
    id: "ai-provider",
    title: "AI provider",
    section: "connections",
    component: AiProviderScreen,
    about:
      "Inspect a provider you connected yourself, choose which of its models reach the agent tab, and remove it. Says what is wrong when the key, the sign-in or the account behind it stops working.",
  },
  {
    id: "provider-models",
    title: "AI provider · Models",
    section: "connections",
    component: ProviderModelsScreen,
    about:
      "Every model a provider offers, with a switch each. Ranked by what we would reach for, and honest about the ones we do not recognise.",
  },
  {
    id: "local-model",
    title: "Local model",
    section: "connections",
    component: LocalModelScreen,
    about:
      "Inspect the small model that runs on the device: what it is good for, what it costs in space, and whether to download or delete it. Used when you are offline, or when a conversation should stay on the phone.",
  },
  {
    id: "local-model-info",
    title: "Local model · How it works",
    section: "connections",
    component: LocalModelInfoScreen,
    about: "What running on the phone buys and costs, and when Eigin reaches for it.",
  },
  {
    id: "provider-select",
    title: "Add a provider",
    section: "connections",
    component: ProviderSelectScreen,
    about:
      "Pick a provider to add, grouped by what you will be asked to do rather than by protocol. Anything not on the list can be connected by address.",
  },
  {
    id: "provider-connect",
    title: "Connect a provider",
    section: "connections",
    component: ProviderConnectScreen,
    about:
      "Connect one provider, whichever way it lets you in: a browser sign-in, an API key, or an address. Nothing reports success before it has been checked.",
  },
  {
    id: "integration",
    title: "Integration",
    section: "connections",
    component: IntegrationScreen,
    about:
      "Inspect one integration: what it is, what it can do for you, and how to remove it. Built-in accounts, servers you run and other agents share this screen, because they are the same thing to the person using them.",
  },
  {
    id: "integration-tools",
    title: "Integration · Offers",
    section: "connections",
    component: OffersScreen,
    about:
      "Everything one connection offers, read-only. There is nothing to choose here, so there is nothing to sort by — only something to find.",
  },
  {
    id: "add-integration",
    title: "Add an integration",
    section: "connections",
    component: AddIntegrationScreen,
    about:
      "Add anything Eigin can reach, in one catalogue sorted by what you want it to do. Anything we have never heard of can be connected by address.",
  },
  {
    id: "connect-integration",
    title: "Connect an integration",
    section: "connections",
    component: ConnectIntegrationScreen,
    about:
      "Connect one integration, whichever way it lets you in: a sign-in, a key, mail settings, or a server that has to be asked what it needs.",
  },

  {
    id: "watch-ask",
    title: "Ask",
    section: "watch",
    component: WatchScreen,
    device: "apple-watch",
    about:
      "A quick command from the wrist, with the phone pocketed and locked. The watch listens and the phone answers, so these four states are everything it ever shows: ready, listening, thinking, answered.",
  },
];
