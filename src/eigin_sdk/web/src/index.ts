import {
  initialize as initializeRust,
  uniffiInitAsync,
  setDiagnosticReceiver as setReceiver,
  updateDiagnosticOptions as updateOptions,
  clearDiagnosticReceiver as clearReceiver,
  DiagnosticLevel,
  type DiagnosticOptions,
  type DiagnosticReceiver,
} from "./generated";

export { DiagnosticLevel, DiagnosticPrivacy } from "./generated";
export type {
  DiagnosticEvent,
  DiagnosticField,
  DiagnosticContext,
  DiagnosticOptions,
  DiagnosticReceiver,
} from "./generated";

function loadRuntime(): Promise<void> {
  return uniffiInitAsync(
    new URL("./generated/eigin_sdk.wasm", import.meta.url),
  );
}

/** Loads the browser runtime and initializes the portable SDK. Safe to repeat. */
export async function initialize(): Promise<void> {
  await loadRuntime();
  await initializeRust();
}

/** Receives future events synchronously. No console output is installed by default. */
export async function setDiagnosticReceiver(
  receiver: DiagnosticReceiver,
  options: DiagnosticOptions = {
    minimumLevel: DiagnosticLevel.Debug,
    includePrivate: false,
  },
): Promise<void> {
  await loadRuntime();
  setReceiver(receiver, options);
}

/** Updates filtering for subsequent events. Previously disclosed values cannot be recalled. */
export async function updateDiagnosticOptions(
  options: DiagnosticOptions,
): Promise<void> {
  await loadRuntime();
  updateOptions(options);
}

/** Detaches the receiver; events already in progress may finish. */
export async function clearDiagnosticReceiver(): Promise<void> {
  await loadRuntime();
  clearReceiver();
}
