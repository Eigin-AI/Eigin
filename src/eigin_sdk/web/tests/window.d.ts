import type { initialize } from "../src";
import type { contracts } from "./contracts";

declare global {
  interface Window {
    contracts: typeof contracts;
    initializeSdk: typeof initialize;
    configureDiagnostics: () => Promise<void>;
  }
}
