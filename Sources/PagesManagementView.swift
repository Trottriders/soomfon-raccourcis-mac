import SwiftUI

struct PagesManagementView: View {
    @ObservedObject var model: DeckModel
    var editKeys: () -> Void
    @State private var deletingPageID: String?
    private let accent = Color(red: 0.39, green: 0.88, blue: 0.74)
    private func associations(_ id: String) -> [ApplicationPage] {
        (model.configuration.applicationPages ?? []).filter { $0.pageID == id }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mes pages").font(.title2).fontWeight(.semibold)
                    Text("Choisis une page pour la renommer, l’associer à un logiciel ou modifier ses touches.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Nouvelle page") { model.addPage() }.disabled((model.configuration.pages ?? []).count >= 50)
            }
            HStack(alignment: .top, spacing: 24) {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(model.configuration.allPages) { page in
                            Button { model.switchPage(page.id) } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: page.id == homePageID ? "house.fill" : "square.grid.3x3.fill")
                                        .foregroundStyle(accent).frame(width: 22)
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text(page.name.trimmingCharacters(in: .whitespacesAndNewlines)).fontWeight(.semibold)
                                        let rules = associations(page.id)
                                        let launchers = model.configuration.launchers(for: page.id)
                                        Text(page.id == homePageID ? "Page d’accueil" : !rules.isEmpty ? rules.map(\.name).joined(separator: ", ") : !launchers.isEmpty ? "Ouverte par : " + launchers.map { $0.title.isEmpty ? "une touche" : $0.title }.joined(separator: ", ") : "Sans logiciel associé")
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                        Text("\(page.keys.filter(\.isConfigured).count) touches configurées")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if page.id == model.activePageID { Image(systemName: "checkmark.circle.fill").foregroundStyle(accent) }
                                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(page.id == model.activePageID ? accent.opacity(0.12) : Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(page.id == model.activePageID ? accent : .clear))
                            }.buttonStyle(.plain).accessibilityLabel("Page \(page.name)")
                        }
                    }
                }.frame(minWidth: 240, idealWidth: 280, maxWidth: 320)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(model.pageName.trimmingCharacters(in: .whitespacesAndNewlines)).font(.title2).fontWeight(.semibold)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Nom de la page").font(.caption).foregroundStyle(.secondary)
                            TextField("Nom de la page", text: Binding(get: { model.pageName }, set: { model.renamePage($0) }))
                                .textFieldStyle(.roundedBorder).accessibilityLabel("Nom de la page")
                        }
                        Button("Modifier les touches") { editKeys() }.buttonStyle(.borderedProminent)
                        Text("Tu peux y placer des raccourcis clavier, macros, logiciels, sites Internet et captures d’écran.")
                            .font(.caption).foregroundStyle(.secondary)
                        let launchers = model.configuration.launchers(for: model.activePageID)
                        if !launchers.isEmpty {
                            Text("Cette page s’ouvre avec la touche : " + launchers.map { $0.title.isEmpty ? "sans titre" : $0.title }.joined(separator: ", "))
                                .font(.caption).foregroundStyle(accent)
                        }
                        Divider()
                        Text("Logiciel associé").font(.headline)
                        if model.activePageID == homePageID {
                            Text("L’accueil reste accessible depuis le boîtier. Crée une autre page pour l’associer à un logiciel.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Créer une page pour un logiciel…") { model.chooseApplicationPage(createPage: true) }
                        } else {
                            if model.currentApplicationPages.isEmpty {
                                Text("Aucun logiciel associé.").foregroundStyle(.secondary)
                            } else {
                                ForEach(model.currentApplicationPages) { rule in
                                    HStack {
                                        Text(rule.name)
                                        Spacer()
                                        Button("Dissocier") { model.removeApplicationPage(rule.bundleID) }.font(.caption)
                                            .accessibilityLabel("Dissocier \(rule.name)")
                                    }
                                }
                            }
                            Button("Choisir un logiciel…") { model.chooseApplicationPage(createPage: false) }
                            Text("Quand tu passes dans ce logiciel, sa page s’affiche sur le boîtier. Cela fonctionne aussi avec les navigateurs. Les deux dernières touches reviennent à l’accueil.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Toggle("Changer de page selon le logiciel actif", isOn: Binding(get: { model.configuration.automaticPagesEnabled ?? true }, set: { model.setAutomaticPagesEnabled($0) }))
                        Divider()
                        HStack {
                            Button("Dupliquer la page") { model.duplicatePage() }.disabled((model.configuration.pages ?? []).count >= 50)
                            if model.activePageID != homePageID {
                                Button("Supprimer la page", role: .destructive) { deletingPageID = model.activePageID }
                            }
                        }
                    }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
                }.frame(maxWidth: .infinity)
            }.frame(maxHeight: .infinity)
        }.alert("Supprimer cette page ?", isPresented: Binding(get: { deletingPageID != nil }, set: { if !$0 { deletingPageID = nil } })) {
            Button("Annuler", role: .cancel) { deletingPageID = nil }
            Button("Supprimer", role: .destructive) {
                if let id = deletingPageID, model.configuration.containsPage(id) {
                    model.switchPage(id); model.deletePage()
                }
                deletingPageID = nil
            }
        } message: { Text("Ses touches seront effacées. Les boutons de navigation reviendront à l’accueil. Les logiciels et sites continueront à s’ouvrir, sans cette page.") }
    }
}
