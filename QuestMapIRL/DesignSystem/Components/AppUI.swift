import SwiftUI

/// Superficies y texto de la interfaz general: fondo negro, superficies gris oscuro. Son fijos
/// (la app es oscura); el color de acento sí viene del estilo de mapa elegido.
enum AppColor {
    static let background = Color.black
    static let surface = Color(hex: 0x1C1C1E)
    static let surfaceRaised = Color(hex: 0x2C2C2E)
    static let separator = Color.white.opacity(0.09)
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: 0x9A9AA2)
    static let danger = Color(hex: 0xFF453A)
}

// MARK: - Botones circulares

/// Botón circular con icono claro. `floating` añade sombra para flotar sobre el mapa.
struct CircleIconButton: View {
    let systemImage: String
    let label: String
    var size: CGFloat = 44
    var isActive = false
    var accent: Color = .white
    var floating = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(isActive ? Color.black : accent)
                .frame(width: size, height: size)
                .background(isActive ? accent : AppColor.surfaceRaised, in: .circle)
                .shadow(color: .black.opacity(floating ? 0.45 : 0), radius: 8, y: 3)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

/// Estado de pulsación común: se hunde un poco y atenúa.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Ajustes

/// Tarjeta oscura que agrupa filas con separadores discretos.
struct SettingsGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct RowDivider: View {
    var body: some View {
        Rectangle().fill(AppColor.separator).frame(height: 1).padding(.leading, 64)
    }
}

/// Fila de ajustes: icono claro dentro de un círculo, título, valor opcional y chevron.
struct SettingsRowLabel: View {
    let systemImage: String
    let title: String
    var value: String?
    var tint: Color = .white
    var showsChevron = true

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(AppColor.surfaceRaised, in: .circle)
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(tint == AppColor.danger ? AppColor.danger : AppColor.textPrimary)
            Spacer(minLength: 8)
            if let value {
                Text(value).font(.subheadline).foregroundStyle(AppColor.textSecondary).lineLimit(1)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

/// Cabecera grande con botón circular de cierre (paneles tipo "Perfil").
struct PanelHeader: View {
    let title: String
    var onClose: (() -> Void)?

    var body: some View {
        HStack {
            Text(title).font(.largeTitle.weight(.bold)).foregroundStyle(AppColor.textPrimary)
            Spacer()
            if let onClose {
                CircleIconButton(systemImage: "xmark", label: "Cerrar", size: 40, action: onClose)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }
}

// MARK: - Buscador

/// Campo de búsqueda del panel inferior: lupa, texto, botón de borrar y acción final (perfil).
struct PanelSearchBar<Trailing: View>: View {
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    var prompt = "Buscar"
    var onSubmit: () -> Void = {}
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColor.textSecondary)
                TextField("", text: $text, prompt: Text(prompt).foregroundStyle(AppColor.textSecondary))
                    .focused(focus)
                    .submitLabel(.search)
                    .onSubmit(onSubmit)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .foregroundStyle(AppColor.textPrimary)
                if !text.isEmpty {
                    Button { text = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(AppColor.textSecondary)
                    }
                    .accessibilityLabel("Borrar texto")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(AppColor.surfaceRaised, in: Capsule())
            trailing
        }
    }
}

// MARK: - Accesos rápidos

struct QuickAccessChip: View {
    let systemImage: String
    let title: String
    var subtitle: String?
    var isSet = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(AppColor.surfaceRaised, in: .circle)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline.weight(.semibold))
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(AppColor.textSecondary).lineLimit(1)
                    }
                }
            }
            .foregroundStyle(isSet ? AppColor.textPrimary : AppColor.textSecondary)
            .padding(.leading, 8)
            .padding(.trailing, 14)
            .frame(minHeight: 48)
            .background(AppColor.surface, in: Capsule())
            .overlay(Capsule().stroke(AppColor.separator, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Tarjetas

/// Tarjeta de categoría de la cuadrícula: icono grande y nombre debajo.
struct CategoryTile: View {
    let systemImage: String
    let title: String
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous).fill(AppColor.surface)
                    ZStack {
                        Circle().fill(AppColor.surfaceRaised)
                        Image(systemName: systemImage)
                            .font(.system(size: 28, weight: .semibold))
                            .opacity(isBusy ? 0.2 : 1)
                        if isBusy { ProgressView() }
                    }
                    .frame(width: 66, height: 66)
                }
                .frame(height: 98)
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(AppColor.textPrimary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title)
    }
}

/// Tarjeta de recomendación: fondo visual propio, degradado oscuro, icono y título grande.
/// No usa fotografías de terceros: la imagen es un dibujo propio hecho con formas.
struct RecommendationCard: View {
    let title: String
    let systemImage: String
    let tint: Color
    var tall = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                RecommendationArtwork(tint: tint)
                LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(.black.opacity(0.45), in: .circle)
                    Text(title)
                        .font(tall ? .title3.weight(.bold) : .headline.weight(.bold))
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }
                .foregroundStyle(.white)
                .padding(14)
            }
            .frame(maxWidth: .infinity)
            .frame(height: tall ? 232 : 110)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title)
    }
}

/// Fondo de las tarjetas: degradado de color con una cuadrícula de "calles" dibujada.
struct RecommendationArtwork: View {
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.45), Color(hex: 0x15181E)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Path { path in
                    let w = proxy.size.width, h = proxy.size.height
                    path.move(to: CGPoint(x: -10, y: h * 0.32)); path.addLine(to: CGPoint(x: w + 10, y: h * 0.18))
                    path.move(to: CGPoint(x: -10, y: h * 0.72)); path.addLine(to: CGPoint(x: w + 10, y: h * 0.58))
                    path.move(to: CGPoint(x: w * 0.28, y: -10)); path.addLine(to: CGPoint(x: w * 0.42, y: h + 10))
                    path.move(to: CGPoint(x: w * 0.74, y: -10)); path.addLine(to: CGPoint(x: w * 0.62, y: h + 10))
                }
                .stroke(.white.opacity(0.16), style: StrokeStyle(lineWidth: 7, lineCap: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Estados

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
            Text(title).font(.headline).foregroundStyle(AppColor.textPrimary).multilineTextAlignment(.center)
            if let message {
                Text(message).font(.subheadline).foregroundStyle(AppColor.textSecondary).multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18).frame(height: 40)
                    .background(AppColor.surfaceRaised, in: Capsule())
                    .foregroundStyle(AppColor.textPrimary)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
    }
}

/// Mensaje de error, aviso o información dentro de un panel.
struct InlineMessage: View {
    enum Kind { case info, warning, error }
    let kind: Kind
    let text: String
    var actionTitle: String?
    var action: (() -> Void)?

    private var symbol: String {
        switch kind {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "wifi.exclamationmark"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(kind == .info ? AppColor.textSecondary : Color.orange)
            Text(text).font(.footnote.weight(.medium)).foregroundStyle(AppColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                Button(actionTitle, action: action).font(.footnote.weight(.bold))
            }
        }
        .padding(12)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Título de sección dentro de un panel.
struct SectionTitle: View {
    let text: String
    var trailingTitle: String?
    var trailingAction: (() -> Void)?

    var body: some View {
        HStack {
            Text(text).font(.title3.weight(.bold)).foregroundStyle(AppColor.textPrimary)
            Spacer()
            if let trailingTitle, let trailingAction {
                Button(trailingTitle, action: trailingAction)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
    }
}
