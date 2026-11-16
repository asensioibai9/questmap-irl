import UIKit
import MapLibre

/// Registra en el estilo la imagen del avatar elegido, con el nombre que usa la capa
/// `user-arrow` del JSON.
enum UserArrowImage {
    static let name = "user-arrow"

    static func register(in style: MLNStyle, avatar: MapAvatar, arrowHex: UInt32) {
        let image = avatar.image(fill: UIColor(hex: arrowHex), border: UIColor(hex: 0x0A0B0D))
        style.setImage(image, forName: name)
    }
}
