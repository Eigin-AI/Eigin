import EiginSDK

extension KnownModelCatalog {
    static func imageInputBudget(width: Int?, height: Int?, model: String?) -> Int {
        EiginSDK.ModelCatalog.imageInputBudget(width: width, height: height, model: model)
    }
}
