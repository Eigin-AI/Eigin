import { initialize as initializeRust, uniffiInitAsync } from "./generated";

/** Loads the browser runtime and initializes the portable SDK. Safe to repeat. */
export async function initialize(): Promise<void> {
  await uniffiInitAsync(new URL("./generated/eigin_sdk.wasm", import.meta.url));
  await initializeRust();
}
