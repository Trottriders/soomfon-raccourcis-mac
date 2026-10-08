import SwiftUI

struct IconAppearanceView: View {
    @Binding var appearance: IconAppearance
    var allowZoom = true
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if allowZoom {
                HStack {
                    Text("Taille de l’icône").foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(appearance.scale * 100)) %").monospacedDigit()
                    Button { appearance.scale = 1 } label: { Image(systemName: "arrow.counterclockwise") }
                        .buttonStyle(.borderless).help("Revenir à 100 %")
                }
                Slider(value: $appearance.scale, in: 0.25...2, step: 0.05).accessibilityLabel("Taille de l’icône")
            }
            HStack {
                Toggle("Fond transparent", isOn: $appearance.transparent)
                Spacer()
                if !appearance.transparent {
                    ColorPicker("Couleur du fond", selection: Binding(get: { Color(nsColor: appearance.color.nsColor) }, set: {
                        appearance.color = DeckColor(NSColor($0))
                    }), supportsOpacity: false).labelsHidden()
                }
            }
        }.font(.caption)
    }
}

@MainActor final class ScreensaverClock: ObservableObject {
    @Published var date = Date()
    @Published var elapsed: Double = 0
    @Published var apps: [ScreensaverAppIcon] = []
}

struct ScreensaverSettingsView: View {
    @ObservedObject var model: DeckModel
    @ObservedObject var clock: ScreensaverClock
    init(model: DeckModel) { self.model = model; self.clock = model.screensaverClock }
    private var settings: ScreensaverConfiguration { model.configuration.effectiveScreensaver }
    private func binding<T>(_ path: WritableKeyPath<ScreensaverConfiguration, T>) -> Binding<T> {
        Binding(get: { settings[keyPath: path] }, set: { value in model.changeScreensaver { $0[keyPath: path] = value } })
    }
    private var previewID: String {
        "\(settings.kind.rawValue)-\(settings.showsSeconds)-\(settings.showDate)-\(settings.imageTick(at: clock.date, elapsed: clock.elapsed))-\(settings.wallpaperPNG?.hashValue ?? 0)-\(model.configuration.effectiveDashboard.clock24Hour)"
    }
    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 14) {
                Text("APERÇU DES 15 TOUCHES").font(.system(size: 11, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
                if let canvas = ScreensaverImage.canvas(settings: settings, date: clock.date, clock: model.configuration.effectiveDashboard, elapsed: clock.elapsed, apps: clock.apps) {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(87), spacing: 10), count: 5), spacing: 10) {
                        ForEach(0..<15, id: \.self) { index in
                            if let crop = canvas.cropping(to: ScreensaverImage.cropRect(index: index)) {
                                Image(nsImage: NSImage(cgImage: crop, size: NSSize(width: 95, height: 95)))
                                    .resizable().frame(width: 87, height: 87).clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }.id(previewID).accessibilityLabel("Aperçu de l’écran de veille")
                }
                Text(model.screensaverActive ? "L’écran de veille est affiché sur le boîtier." : "Les touches reprennent leur fonction au premier appui.")
                    .font(.caption).foregroundStyle(.secondary)
                Button(model.screensaverActive ? "Revenir aux touches" : "Essayer sur le boîtier") {
                    if model.screensaverActive { model.leaveScreensaver() } else { model.previewScreensaver() }
                }.disabled(!model.connected || (!settings.enabled && !model.screensaverActive))
                if settings.usesAnimation {
                    Button("Essayer \(settings.effectiveAnimation.title) sur le boîtier") { model.previewScreensaver(animation: true) }
                        .disabled(!model.connected || !settings.enabled)
                }
            }
            VStack(alignment: .leading, spacing: 17) {
                Text("Écran de veille").font(.title3).fontWeight(.semibold)
                Text("Quand les écrans du Mac s’éteignent, le boîtier devient noir. Tes touches et leur luminosité reviennent quand ils se rallument.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Activer après une inactivité", isOn: binding(\.enabled))
                Toggle("Quitter la veille en bougeant la souris", isOn: Binding(get: { settings.wakesOnMouseMovement }, set: { value in model.changeScreensaver { $0.wakeOnMouseMovement = value } }))
                VStack(alignment: .leading, spacing: 8) {
                    Text(settings.wakesOnMouseMovement ? "Délai sans appui ni mouvement de souris" : "Délai sans appui sur le boîtier").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        TextField("Secondes", value: Binding(get: { settings.delay }, set: { value in model.changeScreensaver { $0.delay = min(3600, max(15, value)) } }), format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 65)
                        Text("secondes")
                        Stepper("Délai", value: binding(\.delay), in: 15...3600, step: 15).labelsHidden()
                    }
                    Text("De 15 secondes à 1 heure.").font(.caption).foregroundStyle(.secondary)
                }
                Picker("Afficher", selection: binding(\.kind)) {
                    ForEach(ScreensaverKind.allCases) { kind in Text(kind.title).tag(kind) }
                }.labelsHidden()
                if settings.kind == .largeClock {
                    Toggle("Afficher les secondes", isOn: Binding(get: { settings.showsSeconds }, set: { value in
                        model.changeScreensaver { $0.showSeconds = value }
                    }))
                    Text("Un chiffre par touche, sur les deux touches en bas à droite.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if settings.kind == .largeClock || settings.kind == .repeatedClock { Toggle("Afficher la date", isOn: binding(\.showDate)) }
                Divider()
                if settings.kind != .matrix {
                    Picker("Puis afficher", selection: Binding(get: { settings.effectiveAnimation }, set: { value in model.changeScreensaver { $0.animation = value } })) {
                        ForEach(ScreensaverAnimation.allCases) { animation in Text(animation.title).tag(animation) }
                    }
                }
                if settings.usesAnimation {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Heure")
                            Spacer()
                            TextField("Secondes", value: Binding(get: { settings.effectiveClockDuration }, set: { value in model.changeScreensaver { $0.clockDuration = min(300, max(5, value)) } }), format: .number).textFieldStyle(.roundedBorder).frame(width: 55)
                            Text("s")
                        }
                        HStack {
                            Text(settings.effectiveAnimation.title)
                            Spacer()
                            TextField("Secondes", value: Binding(get: { settings.effectivePacmanDuration }, set: { value in model.changeScreensaver { $0.pacmanDuration = min(300, max(5, value)) } }), format: .number).textFieldStyle(.roundedBorder).frame(width: 55)
                            Text("s")
                        }
                        if settings.usesPacman { Toggle("Afficher le titre des applications", isOn: Binding(get: { settings.showApplicationTitles ?? false }, set: { value in model.changeScreensaver { $0.showApplicationTitles = value } })) }
                        Text(settings.usesPacman ? "L’heure et Pac-Man alternent. Il mange les icônes des applications ouvertes." : "L’heure et la pluie Matrix alternent. De 5 à 300 secondes par affichage.")
                            .foregroundStyle(.secondary)
                    }.font(.caption)
                }
                if settings.kind == .matrix || settings.effectiveAnimation == .matrix {
                    Toggle("Faire apparaître l’heure dans Matrix", isOn: Binding(get: { settings.showsMatrixClock }, set: { value in model.changeScreensaver { $0.matrixClockEnabled = value } }))
                    HStack {
                        Text("Vitesse de défilement").font(.caption)
                        Spacer()
                        Text(String(format: "× %.2g", settings.effectiveMatrixSpeed)).font(.caption).monospacedDigit()
                    }
                    Slider(value: Binding(get: { settings.effectiveMatrixSpeed }, set: { value in model.changeScreensaver { $0.matrixSpeed = value } }), in: 0.25...3, step: 0.05)
                        .accessibilityLabel("Vitesse de défilement Matrix")
                    Text("Des colonnes de caractères verts tombent à des vitesses différentes, avec une tête brillante et une traînée lumineuse.").font(.caption).foregroundStyle(.secondary)
                    if settings.showsMatrixClock {
                        Text("Les caractères de Matrix assemblent les chiffres sur la rangée du milieu. L’heure reste lisible, puis se désagrège en fragments qui tombent dans la pluie verte.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if settings.kind == .matrix || settings.usesAnimation {
                    Picker("Fluidité", selection: Binding(get: { settings.effectiveAnimationFPS }, set: { value in model.changeScreensaver { $0.animationFPS = value } })) {
                        Text("Économique").tag(4)
                        Text("Fluide").tag(8)
                        Text("Très fluide").tag(12)
                    }.font(.caption)
                }
                Divider()
                Text("Fond d’écran personnel").fontWeight(.medium)
                Button("Choisir une image…") { model.chooseWallpaper() }
                if settings.wallpaperPNG != nil {
                    Button("Retirer le fond d’écran") { model.changeScreensaver { $0.wallpaperPNG = nil } }
                }
                Text("L’image s’étend sur les 15 touches. Tu peux aussi l’afficher derrière l’horloge.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(settings.kind == .largeClock ? "Un chiffre entier par touche, sur la rangée du milieu. Le premier appui revient aux raccourcis." : "Le premier appui quitte la veille sans envoyer de raccourci.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(20).frame(width: 252, alignment: .leading)
                .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
