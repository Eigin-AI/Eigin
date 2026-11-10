import {
  DiagnosticLevel,
  DiagnosticPrivacy,
  type DiagnosticEvent,
  clearDiagnosticReceiver,
  emitDiagnosticFixture,
  setDiagnosticReceiver,
  updateDiagnosticOptions,
} from "./generated";

const defaults = { minimumLevel: DiagnosticLevel.Debug, includePrivate: false };

function assert(condition: boolean, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

export const diagnostics = {
  async privacyAndContextSurviveCallbacks() {
    const events: DiagnosticEvent[] = [];
    setDiagnosticReceiver(
      {
        receive(event) {
          events.push(event);
        },
      },
      defaults,
    );
    try {
      emitDiagnosticFixture();
      updateDiagnosticOptions({ ...defaults, includePrivate: true });
      emitDiagnosticFixture();
      updateDiagnosticOptions(defaults);
      emitDiagnosticFixture();

      assert(events.length === 3, "Expected three diagnostic callbacks");
      const first = events[0];
      assert(first.level === DiagnosticLevel.Info, "Severity changed");
      assert(
        first.context?.operationId === "operation-1",
        "Operation context lost",
      );
      assert(
        first.context?.parentOperationId === "parent-1",
        "Parent context lost",
      );
      const publicField = first.fields.find((field) => field.name === "status");
      assert(
        publicField?.privacy === DiagnosticPrivacy.Public,
        "Public classification lost",
      );
      assert(publicField.value === "ok", "Public payload changed");
      for (const [index, expected] of [
        undefined,
        "private fixture",
        undefined,
      ].entries()) {
        const field = events[index].fields.find(
          (field) => field.name === "detail",
        );
        assert(
          field?.privacy === DiagnosticPrivacy.Private,
          "Private classification lost",
        );
        assert(
          field.value === expected,
          "Private payload did not follow policy",
        );
      }
    } finally {
      clearDiagnosticReceiver();
    }
  },

  async filteringReplacementAndClearControlDelivery() {
    let originalCalls = 0;
    let replacementCalls = 0;
    setDiagnosticReceiver(
      {
        receive() {
          originalCalls++;
        },
      },
      defaults,
    );
    try {
      emitDiagnosticFixture();
      updateDiagnosticOptions({
        ...defaults,
        minimumLevel: DiagnosticLevel.Error,
      });
      emitDiagnosticFixture();
      assert(originalCalls === 1, "Filtered event reached the receiver");
      setDiagnosticReceiver(
        {
          receive() {
            replacementCalls++;
            // Exercise the guard against accidental recursive host emission.
            emitDiagnosticFixture();
          },
        },
        defaults,
      );
      emitDiagnosticFixture();
      assert(originalCalls === 1, "Replaced receiver received an event");
      assert(replacementCalls === 1, "Recursive delivery was not suppressed");
      clearDiagnosticReceiver();
      emitDiagnosticFixture();
      assert(replacementCalls === 1, "Cleared receiver received an event");
    } finally {
      clearDiagnosticReceiver();
    }
  },
};
