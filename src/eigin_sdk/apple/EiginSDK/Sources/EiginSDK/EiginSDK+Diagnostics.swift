import EiginSDKBindings

public extension EiginSDK {
    /// Structured SDK diagnostics routed to a host-owned receiver.
    enum Diagnostics {
        public typealias Event = EiginSDKBindings.DiagnosticEvent
        public typealias Field = EiginSDKBindings.DiagnosticField
        public typealias Context = EiginSDKBindings.DiagnosticContext
        public typealias Level = EiginSDKBindings.DiagnosticLevel
        public typealias Privacy = EiginSDKBindings.DiagnosticPrivacy
        public typealias Options = EiginSDKBindings.DiagnosticOptions
        public typealias Receiver = EiginSDKBindings.DiagnosticReceiver

        /// Installs a destination before SDK operations. Native callbacks may be concurrent.
        public static func setReceiver(
            _ receiver: any Receiver,
            options: Options = .init(minimumLevel: .debug, includePrivate: false)
        ) {
            EiginSDKBindings.setDiagnosticReceiver(receiver: receiver, options: options)
        }

        /// Updates policy for subsequent events; in-flight events retain their original policy.
        public static func updateOptions(_ options: Options) {
            EiginSDKBindings.updateDiagnosticOptions(options: options)
        }

        /// Stops future delivery; in-flight callbacks may finish.
        public static func clearReceiver() {
            EiginSDKBindings.clearDiagnosticReceiver()
        }
    }
}
