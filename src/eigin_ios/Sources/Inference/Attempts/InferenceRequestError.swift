/// No candidate produced useful output within the request's deadline budget.
struct FirstEventTimeout: Error {}

/// A stream ended before producing an eligible race-winning event.
struct StreamEndedWithoutUsefulOutput: Error {}

/// A candidate exceeded its in-memory buffer for events preceding its answer.
struct PreWinnerBufferOverflow: Error {}
