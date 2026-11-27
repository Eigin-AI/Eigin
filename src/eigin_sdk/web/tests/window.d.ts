import type { initialize } from "../src";
import type { promptTests } from "./prompt-catalog";
import type { catalogTests } from "./model-catalog";
import type { contracts } from "./contracts";
import type { providerTests } from "./inference-cancellation";

import type { relayTests } from "./eigin-relay";

declare global {
  interface Window {
    promptTests: typeof promptTests;
    catalogTests: typeof catalogTests;
    relayTests: typeof relayTests;
    relayText: string;
    checkContext: () => Promise<boolean>;
    contracts: typeof contracts;
    providerTests: typeof providerTests;
    initializeSdk: typeof initialize;
    configureDiagnostics: () => Promise<void>;
  }
}
