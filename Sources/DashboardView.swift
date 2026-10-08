import SwiftUI

struct DashboardSettingsView: View {
    @ObservedObject var model: DeckModel
    @ObservedObject var state: DashboardState
    init(model: DeckModel) { self.model = model; self.state = model.dashboardState }
    private var settings: DashboardConfiguration { model.configuration.effectiveDashboard }
    private let accent = Color(red: 0.39, green: 0.88, blue: 0.74)
    private let positions = ["Haut", "Milieu", "Bas"]
    private func toggle(_ keyPath: WritableKeyPath<DashboardConfiguration, Bool>) -> Binding<Bool> {
        Binding(get: { settings[keyPath: keyPath] }, set: { value in model.changeDashboard { $0[keyPath: keyPath] = value } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("LES TROIS ZONES DE TON ÉCRAN").font(.system(size: 11, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
            VStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { index in
                    HStack(spacing: 20) {
                        Group {
                            if state.previews.count == 3, let image = NSImage(data: state.previews[index]) {
                                Image(nsImage: image).resizable().scaledToFit()
                            } else { Color.black.opacity(0.2) }
                        }.frame(width: 82, height: 82)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("\(index + 1) · \(positions[index])").font(.system(size: 14, weight: .semibold)).frame(width: 95, alignment: .leading)
                                Picker("Contenu de la zone \(positions[index].lowercased())", selection: Binding(get: { settings.slots[index].kind }, set: { kind in
                                    model.changeDashboard { $0.slots[index].kind = kind }
                                })) {
                                    ForEach(DashboardKind.allCases) { kind in Text(kind.title).tag(kind) }
                                }.labelsHidden().frame(width: 225)
                                Spacer()
                            }
                            HStack(spacing: 14) {
                                Toggle("Afficher le titre", isOn: Binding(get: { settings.slots[index].showsTitle }, set: { value in
                                    model.changeDashboard { $0.slots[index].showTitle = value }
                                })).accessibilityLabel("Afficher le titre de la zone \(positions[index].lowercased())")
                                if settings.slots[index].showsTitle {
                                    TextField("Titre automatique", text: Binding(get: { settings.slots[index].title ?? "" }, set: { value in
                                        model.changeDashboard { $0.slots[index].title = String(value.prefix(80)) }
                                    })).textFieldStyle(.roundedBorder).frame(width: 190)
                                        .accessibilityLabel("Titre de la zone \(positions[index].lowercased())")
                                }
                            }.font(.caption)
                            switch settings.slots[index].kind {
                            case .clock:
                                Text("L’heure du Mac, actualisée automatiquement.").font(.caption).foregroundStyle(.secondary)
                            case .activeApp:
                                Text("\(state.activeAppName) · l’icône suit l’application au premier plan.").font(.caption).foregroundStyle(.secondary)
                            case .weather:
                                Text(state.weatherStatus).font(.caption).foregroundStyle(.secondary)
                            case .image:
                                HStack {
                                    Button("Choisir une image…") { model.chooseDashboardIcon(index) }
                                    if settings.slots[index].iconPNG != nil {
                                        Button("Retirer") { model.changeDashboard { $0.slots[index].iconPNG = nil } }
                                    }
                                }
                            case .empty:
                                Text("Cette zone reste noire.").font(.caption).foregroundStyle(.secondary)
                            }
                            if settings.slots[index].kind != .empty {
                                IconAppearanceView(appearance: Binding(get: { settings.slots[index].effectiveAppearance }, set: { value in
                                    model.changeDashboard { $0.slots[index].appearance = value }
                                }), allowZoom: [.image, .activeApp].contains(settings.slots[index].kind))
                            }

                        }
                    }.padding(12).background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            HStack(alignment: .top, spacing: 22) {
                if settings.slots.contains(where: { $0.kind == .clock }) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Horloge").fontWeight(.semibold)
                        Toggle("Format 24 heures", isOn: toggle(\.clock24Hour))
                        Toggle("Afficher les secondes", isOn: toggle(\.clockSeconds))
                        Toggle("Afficher la date", isOn: toggle(\.clockDate))
                    }.font(.caption).frame(width: 205, alignment: .leading)
                }
                if settings.slots.contains(where: { $0.kind == .weather }) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Ville de la météo").fontWeight(.semibold)
                            Spacer()
                            Picker("Unité de température", selection: toggle(\.weatherFahrenheit)) {
                                Text("°C").tag(false); Text("°F").tag(true)
                            }.labelsHidden().pickerStyle(.segmented).frame(width: 90)
                        }
                        HStack {
                            TextField("Ville ou code postal", text: $model.cityQuery).textFieldStyle(.roundedBorder)
                                .onSubmit { model.searchCity() }
                            Button(model.searchingCity ? "Recherche…" : "Rechercher") { model.searchCity() }.disabled(model.searchingCity)
                        }
                        if !model.cityResults.isEmpty {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 5) {
                                    ForEach(model.cityResults) { place in
                                        Button(place.label) { model.selectWeatherLocation(place) }.lineLimit(1).buttonStyle(.plain).foregroundStyle(accent)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.frame(maxHeight: 95)
                        } else {
                            Text(settings.location?.label ?? "Aucune ville choisie").foregroundStyle(.secondary).lineLimit(1)
                        }
                        if let error = model.citySearchError { Text(error).foregroundStyle(.orange) }
                        HStack {
                            Link("Données : Open-Meteo", destination: URL(string: "https://open-meteo.com/")!).foregroundStyle(.secondary)
                            Spacer()
                            if settings.location != nil { Button("Actualiser") { model.refreshWeather(force: true) } }
                        }
                    }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Text("Tes choix sont enregistrés automatiquement. Tu peux changer ou inverser les trois contenus.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
