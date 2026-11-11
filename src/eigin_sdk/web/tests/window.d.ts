import type { initialize } from "../src";
import type { contracts } from "./contracts";
import type { providerTests } from "./inference-cancellation";

declare global {
  interface Window {
    checkContext: () => Promise<boolean>;
    contracts: typeof contracts;
    providerTests: typeof providerTests;
    initializeSdk: typeof initialize;
    configureDiagnostics: () => Promise<void>;
  }
}
