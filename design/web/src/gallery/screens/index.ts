import type { Component } from "svelte";
import AddIntegrationScreen from "@gallery/screens/AddIntegrationScreen.svelte";
import AddMcpServerSheetScreen from "@gallery/screens/AddMcpServerSheetScreen.svelte";
import AgentScreen from "@gallery/screens/AgentScreen.svelte";
import CallScreen from "@gallery/screens/CallScreen.svelte";
import ChatListScreen from "@gallery/screens/ChatListScreen.svelte";
import ChatScreen from "@gallery/screens/ChatScreen.svelte";
import ConnectionsScreen from "@gallery/screens/ConnectionsScreen.svelte";
import EiginProviderScreen from "@gallery/screens/EiginProviderScreen.svelte";
import GetCreditsScreen from "@gallery/screens/GetCreditsScreen.svelte";
import IntegrationDetailScreen from "@gallery/screens/IntegrationDetailScreen.svelte";
import LocalModelScreen from "@gallery/screens/LocalModelScreen.svelte";
import RelayInfoScreen from "@gallery/screens/RelayInfoScreen.svelte";
import McpServerScreen from "@gallery/screens/McpServerScreen.svelte";
import ProviderConnectScreen from "@gallery/screens/ProviderConnectScreen.svelte";
import ProviderSelectScreen from "@gallery/screens/ProviderSelectScreen.svelte";
import SettingsScreen from "@gallery/screens/SettingsScreen.svelte";

export interface ScreenEntry {
  id: string;
  title: string;
  /** Which sidebar group the screen folds into. */
  section: string;
  /** The screen itself, so this list is also the routing table. */
  component: Component;
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
];

/**
 * Every screen the gallery can show.
 *
 * A sheet is a screen here: it gets its own entry and renders over whichever
 * screen opens it, because that is the only way to see it in place.
 */
export const screenEntries: ScreenEntry[] = [
  { id: "chat-list", title: "Chat list", section: "primary", component: ChatListScreen },
  { id: "chat", title: "Chat", section: "primary", component: ChatScreen },
  { id: "call", title: "Call", section: "primary", component: CallScreen },
  { id: "agent", title: "Agent", section: "primary", component: AgentScreen },
  { id: "settings", title: "Settings", section: "primary", component: SettingsScreen },

  { id: "connections", title: "Connections", section: "connections", component: ConnectionsScreen },
  {
    id: "eigin-provider",
    title: "Eigin credits",
    section: "connections",
    component: EiginProviderScreen,
  },
  { id: "get-credits", title: "Get credits", section: "connections", component: GetCreditsScreen },
  {
    id: "relay-info",
    title: "How the relay works",
    section: "connections",
    component: RelayInfoScreen,
  },
  {
    id: "provider-select",
    title: "Pick a provider",
    section: "connections",
    component: ProviderSelectScreen,
  },
  {
    id: "provider-connect",
    title: "Connect a provider",
    section: "connections",
    component: ProviderConnectScreen,
  },
  {
    id: "add-integration",
    title: "Add integration",
    section: "connections",
    component: AddIntegrationScreen,
  },
  {
    id: "integration-detail",
    title: "One integration",
    section: "connections",
    component: IntegrationDetailScreen,
  },
  { id: "local-model", title: "Local model", section: "connections", component: LocalModelScreen },
  { id: "mcp-server", title: "MCP server", section: "connections", component: McpServerScreen },
  {
    id: "add-mcp-server",
    title: "Add MCP server",
    section: "connections",
    component: AddMcpServerSheetScreen,
  },
];
