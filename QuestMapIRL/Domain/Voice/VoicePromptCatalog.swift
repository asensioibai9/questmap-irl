import Foundation

/// Identificador ESTABLE de una frase grabable. Es la clave de las grabaciones guardadas: nunca se usa el texto visible
/// como clave, así que corregir un texto no rompe perfiles ya grabados. No cambiar los `rawValue` existentes.
enum VoicePhraseID: String, CaseIterable, Codable, Sendable {
    // Estado
    case startRoute = "state.start"
    case followRoute = "state.follow"
    case recalculating = "state.recalculating"
    case backToRoute = "state.back_to_route"
    case arrived = "state.arrived"
    case destinationRight = "state.destination_right"
    case destinationLeft = "state.destination_left"
    // Direcciones
    case continueStraight = "dir.straight"
    case turnRight = "dir.right"
    case turnLeft = "dir.left"
    case slightRight = "dir.slight_right"
    case slightLeft = "dir.slight_left"
    case sharpRight = "dir.sharp_right"
    case sharpLeft = "dir.sharp_left"
    case keepRight = "dir.keep_right"
    case keepLeft = "dir.keep_left"
    case uTurn = "dir.uturn"
    // Incorporaciones y salidas
    case merge = "road.merge"
    case onRampRight = "road.on_ramp_right"
    case onRampLeft = "road.on_ramp_left"
    case exitRight = "road.exit_right"
    case exitLeft = "road.exit_left"
    case forkRight = "road.fork_right"
    case forkLeft = "road.fork_left"
    // Rotondas
    case enterRoundabout = "roundabout.enter"
    case roundaboutExit1 = "roundabout.exit1"
    case roundaboutExit2 = "roundabout.exit2"
    case roundaboutExit3 = "roundabout.exit3"
    case roundaboutExit4 = "roundabout.exit4"
    case roundaboutExit5 = "roundabout.exit5"
    case roundaboutExit6 = "roundabout.exit6"
    case leaveRoundabout = "roundabout.leave"
    // Distancias (fragmentos)
    case in50m = "dist.50m"
    case in100m = "dist.100m"
    case in200m = "dist.200m"
    case in300m = "dist.300m"
    case in500m = "dist.500m"
    case in800m = "dist.800m"
    case in1km = "dist.1km"
    case in2km = "dist.2km"
}

enum VoicePhraseCategory: String, CaseIterable, Identifiable {
    case state, directions, roads, roundabouts, distances
    var id: String { rawValue }

    var title: String {
        switch self {
        case .state: return "Inicio y estado"
        case .directions: return "Direcciones"
        case .roads: return "Incorporaciones y salidas"
        case .roundabouts: return "Rotondas"
        case .distances: return "Distancias"
        }
    }
}

/// Una frase del catálogo en un idioma.
struct VoicePhrase: Identifiable, Equatable {
    let id: VoicePhraseID
    let text: String
    let category: VoicePhraseCategory
    /// Obligatoria para que el perfil esté «listo para usar». Las opcionales solo amplían lo que se dice con tu voz.
    let required: Bool
    /// Se encadena con otra (p. ej. «En doscientos metros» + «gira a la derecha»): consejo de entonación al grabar.
    let isFragment: Bool
    /// Pista de cómo decirla.
    var hint: String? = nil
}

/// Catálogo de frases por idioma. Revisado contra lo que produce de verdad el motor (tipos y modificadores de OSRM que
/// usa `InstructionBuilder`) y contra los avisos que lanza la navegación (`ActiveNavigationViewModel`).
///
/// NO incluye (el motor no lo da): carriles («mantente en el centro»), «continúa por la vía principal», encadenados
/// «después / y después» ni «ahora» (la navegación anuncia una maniobra cada vez), «la ruta se ha actualizado» y «ubicación no
/// disponible» (no se anuncian por voz). Si en el futuro se añaden, se suben `version` y las frases nuevas aparecen como
/// pendientes en los perfiles existentes, sin borrar nada.
enum VoicePromptCatalog {
    /// Versión del catálogo guardada en cada perfil.
    static let version = 1
    static let supportedLanguages: [(code: String, name: String)] = [("es-ES", "Español (España)")]
    static let defaultLanguage = "es-ES"

    static func phrases(language: String) -> [VoicePhrase] {
        switch language {
        default: return spanish     // por ahora solo español; cada idioma tendrá su propia lista, sin mezclarse
        }
    }

    static func phrase(_ id: VoicePhraseID, language: String) -> VoicePhrase? {
        phrases(language: language).first { $0.id == id }
    }

    static func requiredIDs(language: String) -> Set<VoicePhraseID> {
        Set(phrases(language: language).filter(\.required).map(\.id))
    }

    private static let fragmentHint = "Dila de seguido, sin pausa al principio ni al final: se une con la maniobra."
    private static let maneuverHint = "Empieza en minúscula mentalmente: puede ir detrás de una distancia («En 200 metros, …»)."

    private static let spanish: [VoicePhrase] = [
        VoicePhrase(id: .startRoute, text: "Iniciando ruta", category: .state, required: true, isFragment: false),
        VoicePhrase(id: .followRoute, text: "Continúa por la ruta indicada", category: .state, required: true, isFragment: false),
        VoicePhrase(id: .recalculating, text: "Recalculando ruta", category: .state, required: true, isFragment: false),
        VoicePhrase(id: .backToRoute, text: "Cuando sea posible, vuelve a la ruta indicada", category: .state, required: true, isFragment: false),
        VoicePhrase(id: .arrived, text: "Has llegado a tu destino", category: .state, required: true, isFragment: false),
        VoicePhrase(id: .destinationRight, text: "Tu destino está a la derecha", category: .state, required: false, isFragment: false),
        VoicePhrase(id: .destinationLeft, text: "Tu destino está a la izquierda", category: .state, required: false, isFragment: false),

        VoicePhrase(id: .continueStraight, text: "Continúa recto", category: .directions, required: true, isFragment: true, hint: maneuverHint),
        VoicePhrase(id: .turnRight, text: "Gira a la derecha", category: .directions, required: true, isFragment: true, hint: maneuverHint),
        VoicePhrase(id: .turnLeft, text: "Gira a la izquierda", category: .directions, required: true, isFragment: true, hint: maneuverHint),
        VoicePhrase(id: .slightRight, text: "Gira ligeramente a la derecha", category: .directions, required: true, isFragment: true, hint: maneuverHint),
        VoicePhrase(id: .slightLeft, text: "Gira ligeramente a la izquierda", category: .directions, required: true, isFragment: true, hint: maneuverHint),
        VoicePhrase(id: .sharpRight, text: "Gira pronunciadamente a la derecha", category: .directions, required: false, isFragment: true, hint: maneuverHint),
        VoicePhrase(id: .sharpLeft, text: "Gira pronunciadamente a la izquierda", category: .directions, required: false, isFragment: true, hint: maneuverHint),
        VoicePhrase(id: .keepRight, text: "Mantente a la derecha", category: .directions, required: false, isFragment: true, hint: maneuverHint),
        VoicePhrase(id: .keepLeft, text: "Mantente a la izquierda", category: .directions, required: false, isFragment: true, hint: maneuverHint),
        VoicePhrase(id: .uTurn, text: "Realiza un cambio de sentido cuando esté permitido", category: .directions, required: false, isFragment: true, hint: maneuverHint),

        VoicePhrase(id: .merge, text: "Incorpórate a la vía", category: .roads, required: false, isFragment: true, hint: maneuverHint),
        VoicePhrase(id: .onRampRight, text: "Toma la incorporación a la derecha", category: .roads, required: false, isFragment: true, hint: maneuverHint),
        VoicePhrase(id: .onRampLeft, text: "Toma la incorporación a la izquierda", category: .roads, required: false, isFragment: true, hint: maneuverHint),
        VoicePhrase(id: .exitRight, text: "Toma la salida a la derecha", category: .roads, required: false, isFragment: true, hint: maneuverHint),
        VoicePhrase(id: .exitLeft, text: "Toma la salida a la izquierda", category: .roads, required: false, isFragment: true, hint: maneuverHint),
        VoicePhrase(id: .forkRight, text: "En la bifurcación, mantente a la derecha", category: .roads, required: false, isFragment: true, hint: maneuverHint),
        VoicePhrase(id: .forkLeft, text: "En la bifurcación, mantente a la izquierda", category: .roads, required: false, isFragment: true, hint: maneuverHint),

        VoicePhrase(id: .enterRoundabout, text: "Entra en la rotonda", category: .roundabouts, required: false, isFragment: true, hint: maneuverHint),
        VoicePhrase(id: .roundaboutExit1, text: "En la rotonda, toma la primera salida", category: .roundabouts, required: true, isFragment: true, hint: maneuverHint),
        VoicePhrase(id: .roundaboutExit2, text: "En la rotonda, toma la segunda salida", category: .roundabouts, required: true, isFragment: true, hint: maneuverHint),
        VoicePhrase(id: .roundaboutExit3, text: "En la rotonda, toma la tercera salida", category: .roundabouts, required: true, isFragment: true, hint: maneuverHint),
        VoicePhrase(id: .roundaboutExit4, text: "En la rotonda, toma la cuarta salida", category: .roundabouts, required: false, isFragment: true, hint: maneuverHint),
        VoicePhrase(id: .roundaboutExit5, text: "En la rotonda, toma la quinta salida", category: .roundabouts, required: false, isFragment: true, hint: maneuverHint),
        VoicePhrase(id: .roundaboutExit6, text: "En la rotonda, toma la sexta salida", category: .roundabouts, required: false, isFragment: true, hint: maneuverHint),
        VoicePhrase(id: .leaveRoundabout, text: "Sal de la rotonda", category: .roundabouts, required: false, isFragment: true, hint: maneuverHint),

        VoicePhrase(id: .in50m, text: "En cincuenta metros", category: .distances, required: false, isFragment: true, hint: fragmentHint),
        VoicePhrase(id: .in100m, text: "En cien metros", category: .distances, required: true, isFragment: true, hint: fragmentHint),
        VoicePhrase(id: .in200m, text: "En doscientos metros", category: .distances, required: true, isFragment: true, hint: fragmentHint),
        VoicePhrase(id: .in300m, text: "En trescientos metros", category: .distances, required: false, isFragment: true, hint: fragmentHint),
        VoicePhrase(id: .in500m, text: "En quinientos metros", category: .distances, required: true, isFragment: true, hint: fragmentHint),
        VoicePhrase(id: .in800m, text: "En ochocientos metros", category: .distances, required: false, isFragment: true, hint: fragmentHint),
        VoicePhrase(id: .in1km, text: "En un kilómetro", category: .distances, required: false, isFragment: true, hint: fragmentHint),
        VoicePhrase(id: .in2km, text: "En dos kilómetros", category: .distances, required: false, isFragment: true, hint: fragmentHint),
    ]
}

// MARK: - De la navegación real a frases grabadas

/// Una indicación lista para decir: el texto COMPLETO (voz del sistema) y, si se puede formar con seguridad, la secuencia
/// de frases grabadas equivalente. Ambas salen del mismo dato del motor.
struct VoiceCue: Equatable {
    var text: String
    /// nil = no hay una forma segura de decirla con grabaciones genéricas.
    var phrases: [VoicePhraseID]?
    /// La versión del sistema dice un dato importante que las grabaciones no (p. ej. número de salida): en modo híbrido
    /// se prefiere la voz del sistema.
    var systemSaysMore = false

    static func text(_ text: String) -> VoiceCue { VoiceCue(text: text, phrases: nil) }
}

enum VoicePromptComposer {
    /// Frases de distancia disponibles y su valor en metros.
    static let distancePhrases: [(meters: Double, id: VoicePhraseID)] = [
        (50, .in50m), (100, .in100m), (200, .in200m), (300, .in300m), (500, .in500m), (800, .in800m), (1000, .in1km), (2000, .in2km),
    ]

    /// Distancia grabada que corresponde a la real. Tolerancia: ±20 % (mínimo ±30 m). Fuera de eso no hay frase: mejor el
    /// respaldo que anunciar una distancia claramente falsa. En millas no hay grabaciones (el catálogo es métrico).
    static func distancePhrase(meters: Double, metric: Bool) -> VoicePhraseID?? {
        guard meters >= 40 else { return .some(nil) }        // muy cerca: solo la maniobra, sin distancia (como la voz del sistema)
        guard metric else { return nil }
        let best = distancePhrases.min { abs($0.meters - meters) < abs($1.meters - meters) }!
        guard abs(best.meters - meters) <= max(30, best.meters * 0.2) else { return nil }
        return .some(best.id)
    }

    /// Frase de la maniobra a partir de los datos ESTRUCTURADOS del motor. nil si no hay una frase genérica correcta.
    static func maneuverPhrase(_ maneuver: ManeuverInfo?) -> VoicePhraseID? {
        guard let maneuver else { return nil }
        let m = maneuver.modifier ?? ""
        switch maneuver.type {
        case "turn", "end of road":
            return turnPhrase(m)
        case "continue":
            switch m {
            case "", "straight": return .continueStraight
            case "uturn": return .uTurn
            case "slight right", "right", "sharp right": return .keepRight
            case "slight left", "left", "sharp left": return .keepLeft
            default: return nil
            }
        case "new name", "notification":
            return .continueStraight
        case "depart":
            return .followRoute
        case "merge":
            return .merge
        case "on ramp", "ramp":
            if m.contains("left") { return .onRampLeft }
            if m.contains("right") { return .onRampRight }
            return nil
        case "off ramp":
            if m.contains("left") { return .exitLeft }
            if m.contains("right") { return .exitRight }
            return nil
        case "fork":
            if m.contains("left") { return .forkLeft }
            if m.contains("right") { return .forkRight }
            return m == "straight" ? .continueStraight : nil
        case "roundabout", "rotary":
            guard let exit = maneuver.exit else { return .enterRoundabout }
            // Salidas por encima de la sexta: no hay grabación y NUNCA se dice otro número.
            let exits: [Int: VoicePhraseID] = [1: .roundaboutExit1, 2: .roundaboutExit2, 3: .roundaboutExit3,
                                               4: .roundaboutExit4, 5: .roundaboutExit5, 6: .roundaboutExit6]
            return exits[exit]
        case "exit roundabout", "exit rotary":
            return .leaveRoundabout
        case "arrive":
            if m == "right" { return .destinationRight }
            if m == "left" { return .destinationLeft }
            return .arrived
        default:
            return nil              // «roundabout turn» y tipos desconocidos: respaldo
        }
    }

    private static func turnPhrase(_ m: String) -> VoicePhraseID? {
        switch m {
        case "right": return .turnRight
        case "left": return .turnLeft
        case "slight right": return .slightRight
        case "slight left": return .slightLeft
        case "sharp right": return .sharpRight
        case "sharp left": return .sharpLeft
        case "straight": return .continueStraight
        case "uturn": return .uTurn
        default: return nil
        }
    }

    /// Indicación de maniobra: mismo texto que hasta ahora para la voz del sistema y, si es posible, distancia + maniobra.
    static func maneuverCue(step: RouteStep?, instruction: String, distance: Double, metric: Bool) -> VoiceCue {
        let text = ManeuverFormatter.spoken(instruction: instruction, distance: distance, metric: metric)
        var phrase = maneuverPhrase(step?.maneuver)
        // «Has llegado» con grabación solo cuando el motor CONFIRMA la llegada (aviso aparte); al acercarse solo vale
        // «tu destino está a la derecha/izquierda».
        if phrase == .arrived { phrase = nil }
        guard let maneuverPhrase = phrase,
              case .some(let distanceID) = distancePhrase(meters: distance, metric: metric) else {
            return VoiceCue(text: text, phrases: nil)
        }
        let phrases = (distanceID.map { [$0] } ?? []) + [maneuverPhrase]
        return VoiceCue(text: text, phrases: phrases, systemSaysMore: step?.maneuver?.hasVariableDetail ?? false)
    }
}

// MARK: - Qué se reproduce de verdad

/// Qué hacer con una indicación que no se puede decir con grabaciones.
enum VoiceFallbackStrategy: String, CaseIterable, Identifiable {
    /// Lo que falte se dice ENTERO con la voz del sistema (nunca mezclando voces palabra por palabra).
    case hybrid
    /// Solo grabaciones: lo que no se pueda decir con seguridad queda SOLO EN PANTALLA (sin voz).
    case recordingsOnly
    var id: String { rawValue }

    var title: String {
        switch self {
        case .hybrid: return "Híbrido (recomendado)"
        case .recordingsOnly: return "Solo mis grabaciones"
        }
    }

    var explanation: String {
        switch self {
        case .hybrid:
            return "Tu voz cuando hay grabación para esa indicación; si no, la indicación completa con la voz del sistema. Nunca se mezclan las dos voces en una misma frase."
        case .recordingsOnly:
            return "Solo suena tu voz. Las indicaciones sin grabación adecuada (nombres de calles, salidas numeradas, rotondas de más de seis salidas, distancias no grabadas, millas) se verán en pantalla pero NO se dirán."
        }
    }
}

enum VoicePlayback: Equatable {
    case recordings([VoicePhraseID])
    case system(String)
    /// Solo en pantalla (modo «solo grabaciones» sin combinación segura).
    case silent
}

enum VoicePlaybackPlanner {
    static func plan(_ cue: VoiceCue, available: Set<VoicePhraseID>, strategy: VoiceFallbackStrategy) -> VoicePlayback {
        if let phrases = cue.phrases, !phrases.isEmpty, phrases.allSatisfy(available.contains),
           !(strategy == .hybrid && cue.systemSaysMore) {
            return .recordings(phrases)
        }
        return strategy == .hybrid ? .system(cue.text) : .silent
    }
}

/// Estado de un perfil a partir de sus grabaciones.
struct VoiceProfileProgress: Equatable {
    var recorded: Int
    var total: Int
    var missingRequired: [VoicePhraseID]

    var isReady: Bool { missingRequired.isEmpty }

    static func make(recorded: Set<VoicePhraseID>, language: String) -> VoiceProfileProgress {
        let phrases = VoicePromptCatalog.phrases(language: language)
        return VoiceProfileProgress(recorded: phrases.filter { recorded.contains($0.id) }.count,
                                    total: phrases.count,
                                    missingRequired: phrases.filter { $0.required && !recorded.contains($0.id) }.map(\.id))
    }

    /// Se puede activar si está listo, o si está incompleto pero el respaldo es la voz del sistema (híbrido).
    func canActivate(strategy: VoiceFallbackStrategy) -> Bool {
        isReady || (strategy == .hybrid && recorded > 0)
    }
}
