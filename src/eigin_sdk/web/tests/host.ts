import {
  initialize,
  setDiagnosticReceiver,
  updateDiagnosticOptions,
  clearDiagnosticReceiver,
  DiagnosticLevel,
} from "../src";

window.initializeSdk = initialize;
window.configureDiagnostics = async () => {
  let received = false;
  await setDiagnosticReceiver({
    receive() {
      received = true;
    },
  });
  try {
    await initialize();
    await updateDiagnosticOptions({
      minimumLevel: DiagnosticLevel.Warning,
      includePrivate: false,
    });
    if (received) throw new Error("No-op initialization emitted diagnostics");
  } finally {
    await clearDiagnosticReceiver();
  }
};
