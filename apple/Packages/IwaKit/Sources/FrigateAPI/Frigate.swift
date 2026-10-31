import Foundation

public enum Frigate {
    /// The decoder for every Frigate response.
    ///
    /// Models declare their own coding keys. Never set `.convertFromSnakeCase` here: it also rewrites
    /// dictionary keys, so cameras named `front_door` would come back as `frontDoor`.
    public static func decoder() -> JSONDecoder {
        JSONDecoder()
    }
}
