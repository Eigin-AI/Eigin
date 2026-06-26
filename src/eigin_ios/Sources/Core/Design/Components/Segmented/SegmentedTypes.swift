import Foundation

/// One option in an `AppSegmentedControl`. Pairs a display `label` with the
/// `value` the control reports back through its action. The value doubles as the
/// identity, so values must be unique within a control.
struct AppSegment<Value: Hashable>: Identifiable {
    let value: Value
    let label: String

    var id: Value {
        value
    }

    init(_ label: String, value: Value) {
        self.label = label
        self.value = value
    }
}
