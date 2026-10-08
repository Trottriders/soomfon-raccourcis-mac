import SwiftUI

struct DeckView: View {
    @ObservedObject var model: DeckModel
    @State private var section = 0
    private let accent = Color(red: 0.39, green: 0.88, blue: 0.74)
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Soomfon Raccourcis").font(.system(size: 27, weight: .semibold))
                    HStack(spacing: 7) {
                        Circle().fill(model.connected ? accent : .orange).frame(width: 7, height: 7)
                        Text(model.status).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Arrêter les actions") { model.cancelActions() }.font(.caption)
                Toggle("En pause", isOn: $model.paused).toggleStyle(.switch)
            }
            Picker("Configurer", selection: $section) {
                Text("Touches").tag(0); Text("Pages").tag(3); Text("Bande de droite").tag(1); Text("Veille").tag(2)
            }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 560).onChange(of: section) { model.recording = false }
            if section == 0 {
                if !model.trusted {
                    HStack {
                        Image(systemName: "keyboard")
                        Text("Autorise Soomfon Raccourcis dans Accessibilité pour envoyer les raccourcis.").font(.caption)
                        Spacer()
                        Button("Ouvrir les réglages") { model.requestAccessibility() }.font(.caption)
                    }.padding(12).background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                }
                PagesBarView(model: model, showPages: { section = 3 })
                GeometryReader { layout in
                let gridWidth = min(720, max(420, min(layout.size.width * 0.52, (layout.size.height - 190) / 3 * 5 + 40)))
                let cellSize = (gridWidth - 40) / 5
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("\(model.pageName.uppercased()) · 15 TOUCHES").font(.system(size: 11, weight: .semibold)).tracking(1.3).foregroundStyle(.secondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(cellSize), spacing: 10), count: 5), spacing: 10) {
                            ForEach(0..<15, id: \.self) { index in
                                let key = model.currentKeys[index]
                                Button { model.select(index) } label: {
                                    Group {
                                        if model.keyPreviews.indices.contains(index) {
                                            Image(nsImage: model.keyPreviews[index]).resizable()
                                        } else { Color.black }
                                    }.frame(width: cellSize, height: cellSize).clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(model.pressed == index ? Color.orange : model.selected == index ? accent : Color.white.opacity(0.08), lineWidth: model.selected == index || model.pressed == index ? 2 : 1))
                                }.buttonStyle(.plain).accessibilityLabel("Touche \(index + 1), \(key.title), \(key.actionLabel)")
                            }
                        }
                        Text(model.activity).font(.caption).foregroundStyle(.secondary).frame(height: 36, alignment: .topLeading)
                        Toggle("Vérifier les boutons sans exécuter d’action", isOn: $model.testMode).font(.caption)
                        if let progress = model.macroProgress { Text(progress).font(.caption).foregroundStyle(accent) }
                        Spacer()
                        Text("Enregistré automatiquement. Choisis une touche, puis son action à droite.").font(.caption).foregroundStyle(.secondary)
                    }.frame(width: gridWidth, alignment: .topLeading)
                    KeyEditorView(model: model).frame(maxWidth: .infinity, maxHeight: .infinity)
                }.frame(maxHeight: .infinity)
                }
            } else if section == 3 {
                PagesManagementView(model: model, editKeys: { section = 0 })
            } else {
                ScrollView {
                    if section == 1 { DashboardSettingsView(model: model) }
                    else { ScreensaverSettingsView(model: model) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            Divider()
            HStack(spacing: 18) {
                Text("Luminosité").font(.caption).foregroundStyle(.secondary)
                Slider(value: Binding(get: { Double(model.configuration.brightness) }, set: { model.configuration.brightness = Int($0); model.save() }), in: 0...100, step: 5).frame(width: 110)
                Picker("Orientation", selection: Binding(get: { model.configuration.imageRotation }, set: { model.configuration.imageRotation = $0; model.save() })) {
                    ForEach([90,0,180,270], id: \.self) { Text("\($0)°").tag($0) }
                }.frame(width: 165)
                Spacer()
                Menu {
                    Button("Exporter la configuration…") { model.exportConfiguration() }
                    Button("Importer une configuration…") { model.importConfiguration() }
                    Button("Nettoyer l’écran et renvoyer les touches") { model.renderAll(reinitialize: true) }
                    Button("Réparer la connexion au boîtier") { model.reconnectDeck() }
                } label: { Image(systemName: "ellipsis.circle").font(.title3) }.menuStyle(.borderlessButton).frame(width: 26)
            }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.orange).lineLimit(2).textSelection(.enabled) }
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(red: 0.075, green: 0.09, blue: 0.115))
            .preferredColorScheme(.dark).tint(accent)
    }
}
