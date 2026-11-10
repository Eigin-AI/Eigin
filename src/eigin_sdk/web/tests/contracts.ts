import { diagnostics } from "./diagnostics";
import {
  BindingTestError,
  InitializationError,
  PendingOperation,
  failInitializationFixture,
  uniffiInitAsync,
} from "./generated";

function assert(condition: boolean, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

async function rejection(operation: Promise<unknown>): Promise<unknown> {
  try {
    await operation;
  } catch (error) {
    return error;
  }
  throw new Error("Expected a typed error, but operation succeeded");
}

export const contracts = {
  diagnostics,
  async initializationErrorPreservesReason() {
    const error = await rejection(failInitializationFixture());
    assert(
      InitializationError.Unavailable.instanceOf(error),
      "Expected InitializationError.Unavailable",
    );
    assert(
      InitializationError.Unavailable.getInner(error).reason ===
        "binding fixture",
      "Initialization error lost its reason",
    );
  },

  async pendingSuccessPreservesValue() {
    const operation = new PendingOperation();
    const result = operation.run();
    await operation.waitUntilPending();
    operation.succeed("host completion");
    assert((await result) === "host completion", "Success payload changed");
  },

  async pendingFailurePreservesVariantAndPayload() {
    const operation = new PendingOperation();
    const result = rejection(operation.run());
    await operation.waitUntilPending();
    operation.fail(42, "host failure");
    const error = await result;
    assert(
      BindingTestError.Rejected.instanceOf(error),
      "Expected BindingTestError.Rejected",
    );
    const payload = BindingTestError.Rejected.getInner(error);
    assert(payload.code === 42, "Error code changed");
    assert(payload.reason === "host failure", "Error reason changed");
  },

  async operationsCompleteIndependently() {
    const first = new PendingOperation();
    const second = new PendingOperation();
    let firstCompleted = false;
    const firstResult = first.run().then((value) => {
      firstCompleted = true;
      return value;
    });
    const secondResult = second.run();
    await Promise.all([first.waitUntilPending(), second.waitUntilPending()]);
    second.succeed("second");
    assert((await secondResult) === "second", "Second payload changed");
    assert(!firstCompleted, "Completing second also completed first");
    first.succeed("first");
    assert((await firstResult) === "first", "First payload changed");
  },
};

await uniffiInitAsync(new URL("./generated/eigin_sdk.wasm", import.meta.url));
window.contracts = contracts;
