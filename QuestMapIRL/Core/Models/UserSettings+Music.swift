import Foundation

extension UserSettings {
    var musicService: MusicServiceID {
        get { MusicServiceID(rawValue: musicServiceRaw) ?? .appleMusic }
        set { musicServiceRaw = newValue.rawValue }
    }

    var connectedMusicServices: Set<MusicServiceID> {
        get {
            var set = Set(musicConnectedServicesRaw.split(separator: ",").compactMap { MusicServiceID(rawValue: String($0)) })
            if musicConnectedServicesRaw.isEmpty && musicConnected { set.insert(.appleMusic) }   // preferencia de la versión anterior
            return set
        }
        set {
            musicConnectedServicesRaw = MusicServiceID.allCases.filter(newValue.contains).map(\.rawValue).joined(separator: ",")
            musicConnected = newValue.contains(.appleMusic)
        }
    }
}
