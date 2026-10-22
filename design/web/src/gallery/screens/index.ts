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
import ErrorDetailScreen from "@gallery/screens/ErrorDetailScreen.svelte";
import GetCreditsScreen from "@gallery/screens/GetCreditsScreen.svelte";
import IntegrationScreen from "@gallery/screens/IntegrationScreen.svelte";
import OffersScreen from "@gallery/screens/OffersScreen.svelte";
import LocalModelInfoScreen from "@gallery/screens/LocalModelInfoScreen.svelte";
import LocalModelScreen from "@gallery/screens/LocalModelScreen.svelte";
import RelayInfoScreen from "@gallery/screens/RelayInfoScreen.svelte";
import RelayConsentScreen from "@gallery/screens/RelayConsentScreen.svelte";
import ProviderConnectScreen from "@gallery/screens/ProviderConnectScreen.svelte";
import ProviderSelectScreen from "@gallery/screens/ProviderSelectScreen.svelte";
import SettingsScreen from "@gallery/screens/SettingsScreen.svelte";
import ToolDetailScreen from "@gallery/screens/ToolDetailScreen.svelte";
import WatchScreen from "@gallery/screens/WatchScreen.svelte";
import OnboardingFlow from "@gallery/screens/onboarding/OnboardingFlow.svelte";
import IntegrationInChatScreen from "@gallery/screens/IntegrationInChatScreen.svelte";
import ConnectPlatformScreen from "@gallery/screens/platform/ConnectPlatformScreen.svelte";
import PlatformIntegrationScreen from "@gallery/screens/platform/PlatformIntegrationScreen.svelte";

export interface ScreenEntry {
  id: string;
  title: string;
  /** Which sidebar group the screen folds into. */
  section: string;
  /** The screen itself, so this list is also the routing table. */
  component: Component;
  /** Props for the component, so one screen can be entered at several points. */
  props?: Record<string, unknown>;
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
  { id: "onboarding", title: "Onboarding" },
  { id: "connections", title: "Connections" },
  { id: "sheets", title: "Sheets" },
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

  /* Onboarding is one flow entered at each step: every page plays on from
     where it starts, with the avatar carried across the setup steps. */
  {
    id: "onboarding-welcome",
    title: "Welcome",
    section: "onboarding",
    component: OnboardingFlow,
    props: { start: "welcome" },
    about:
      "First launch. The avatar lands big and centred at full power, holds a beat, then settles and speaks. Play on from here to walk the whole flow.",
  },
  {
    id: "onboarding-name",
    title: "Name",
    section: "onboarding",
    component: OnboardingFlow,
    props: { start: "name" },
    about:
      "Asks what to call you, and answers why a private app wants to know. The ring appears from here on and fills a little with each step.",
  },
  {
    id: "onboarding-priority",
    title: "Priority",
    section: "onboarding",
    component: OnboardingFlow,
    props: { start: "priority" },
    about:
      "What you are hoping for, as a carousel of cards. The choice is seeded into the first conversation so the agent can shape itself around it.",
  },
  {
    id: "onboarding-inference",
    title: "Inference",
    section: "onboarding",
    component: OnboardingFlow,
    props: { start: "inference" },
    about:
      "Gives the agent a brain. Eigin's cloud is the default and asks for credits first if you have none; your own provider is second; the offline model downloads in the background.",
  },
  {
    id: "onboarding-conversation",
    title: "Conversation",
    section: "onboarding",
    component: OnboardingFlow,
    props: { start: "conversation" },
    about:
      "The agent gets to know you and writes what it learns into its core, while the header avatar fills. Scripted here: your next reply waits in the composer. It ends when the agent calls done.",
  },
  {
    id: "onboarding-reveal",
    title: "Agent reveal",
    section: "onboarding",
    component: OnboardingFlow,
    props: { start: "reveal" },
    about:
      "The hero moment: the Eigin mark blooms into the agent's face, then it names itself and says what it is for. Tapping through hands off to the first chat.",
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
    about: "Buy a pack of credits, or restore an earlier purchase.",
  },
  {
    id: "relay-consent",
    title: "Eigin Relay · Share",
    section: "connections",
    component: RelayConsentScreen,
    about:
      "Asked before the first conversation goes through the relay: what is shared, where it goes, and whether that is all right.",
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
      "Connect one provider, whichever way it lets you in: a browser sign-in, an API key, or an address. Nothing reports success before it has been checked, and nothing is saved until you allow sharing with it.",
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
    id: "integration-in-chat",
    title: "Integration · In chat",
    section: "connections",
    component: IntegrationInChatScreen,
    about:
      "The agent activates a skill whose integration isn't connected. The call waits and a connect sheet opens over the chat, like a permission request: one integration goes straight to its own sheet, several are offered to pick from. It asks once; after a no, the agent says where to connect instead.",
  },
  {
    id: "platform-integration",
    title: "Platform integration",
    section: "connections",
    component: PlatformIntegrationScreen,
    about:
      "An integration iOS gives permission for: Apple Health, Calendar, Reminders or Location. What Eigin reads and saves, kind by kind. Switches narrow what Eigin uses; the link out changes what iOS allows, since only iOS can take a permission back.",
  },
  {
    id: "connect-platform-integration",
    title: "Platform integration · Connect",
    section: "connections",
    component: ConnectPlatformScreen,
    about:
      "Says what Eigin will read and save before iOS asks. The only way in, whether it opens from the catalogue or from a chat.",
  },

  {
    id: "tool-detail",
    title: "Tool detail",
    section: "sheets",
    component: ToolDetailScreen,
    about:
      "One tool call, opened from the feed that ran it: the state it is in, what it was asked, and what came back. Every state answers for itself, including a call that finished with nothing to show.",
  },

  {
    id: "error-detail",
    title: "Error detail",
    section: "sheets",
    component: ErrorDetailScreen,
    about:
      "What a provider said when a turn failed. The header carries the plain reading and what to do about it; the response itself is read out as facts. Nothing is held back, so there is no raw view to open — only a way to copy it.",
  },

  {
    id: "watch-ask",
    title: "Ask",
    section: "watch",
    component: WatchScreen,
    device: "apple-watch",
    about:
      "A quick command from the wrist, with the phone pocketed and locked. Push to talk, and the answer arrives by notification — so these three states are everything it ever shows: ready, listening, sending.",
  },
];
