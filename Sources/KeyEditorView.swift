import SwiftUI

struct PagesBarView: View {
    @ObservedObject var model: DeckModel
    var showPages: () -> Void
    var body: some View {
        HStack(spacing: 14) {
            Picker("Page à modifier", selection: Binding(get: { model.activePageID }, set: { model.switchPage($0) })) {
                ForEach(model.configuration.allPages) { page in Text(page.name).tag(page.id) }
            }.frame(maxWidth: 340)
            Button("Voir toutes les pages", action: showPages)
            Spacer()
            Text("Choisis une touche pour modifier son action.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ShortcutControls: View {
    @ObservedObject var model: DeckModel
    var step: MacroStep? = nil
    private var shortcut: Shortcut? { step?.shortcut ?? (step == nil ? model.selectedKey.shortcut : nil) }
    private var selectedCode: Int { shortcut == nil || shortcut!.isModifiersOnly ? -1 : Int(shortcut!.keyCode) }
    private var characterChoices: [ShortcutKeyChoice] { ShortcutKeyChoice.characters }
    private var isRecording: Bool { model.isRecording(step: step?.id) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(shortcut?.display ?? "Aucun raccourci").font(.system(size: 21, weight: .medium))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                ForEach(ShortcutModifierChoice.all) { modifier in
                    Toggle(modifier.title, isOn: Binding(get: {
                        NSEvent.ModifierFlags(rawValue: UInt(shortcut?.modifiers ?? 0)).contains(modifier.flag)
                    }, set: { value in model.composeShortcut(step: step?.id, modifier: modifier.flag, enabled: value) }))
                }
            }.font(.caption)
            Picker("Touche", selection: Binding(get: { selectedCode }, set: { value in
                model.composeShortcut(step: step?.id, keyCode: value)
            })) {
                Text("Aucune · modificateurs seuls").tag(-1)
                Section("Lettres et caractères") {
                    ForEach(characterChoices) { key in Text(key.label).tag(key.id) }
                }
                Section("Touches spéciales") {
                    ForEach(ShortcutKeyChoice.specials) { key in Text(key.label).tag(key.id) }
                }
                if let shortcut, !shortcut.isModifiersOnly, !ShortcutKeyChoice.all.contains(where: { $0.code == shortcut.keyCode }) {
                    Text(shortcut.keyLabel).tag(Int(shortcut.keyCode))
                }
            }
            HStack {
                Button(isRecording ? "Annuler" : "Enregistrer…") {
                    if isRecording { model.recording = false } else { model.beginRecording(step: step?.id) }
                }
                Menu("Choisir") {
                    ForEach(Preset.all) { preset in
                        Button("\(preset.title)   \(preset.assignment.shortcut!.display)") {
                            model.recording = false
                            if let step { model.updateMacroStep(step.id) { $0.shortcut = preset.assignment.shortcut } }
                            else { model.preset(preset) }
                        }
                    }
                }
            }
            if isRecording { Text("Appuie sur la combinaison. Échap pour annuler.").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct MacroEditorView: View {
    @ObservedObject var model: DeckModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Étapes de la macro").fontWeight(.medium)
                Spacer()
                Menu {
                    Button("Raccourci clavier") { model.addMacroStep(.shortcut) }
                    Button("Insérer du texte") { model.addMacroStep(.text) }
                    Button("Pause") { model.addMacroStep(.wait) }
                    Button("Ouvrir une application") { model.addMacroStep(.application) }
                    Button("Ouvrir un site Internet") { model.addMacroStep(.website) }
                } label: { Label("Ajouter", systemImage: "plus") }.disabled(model.selectedKey.effectiveMacro.count >= 100)
            }
            ForEach(Array(model.selectedKey.effectiveMacro.enumerated()), id: \.element.id) { index, step in
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 8) {
                        Text("\(index + 1) · \(step.kind == .wait ? "Pause" : step.kind == .application ? "Application" : step.kind == .website ? "Site Internet" : step.kind == .text ? "Texte" : "Raccourci")").fontWeight(.medium)
                        Spacer()
                        Button { model.moveMacroStep(step.id, offset: -1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0).help("Monter l’étape")
                        Button { model.moveMacroStep(step.id, offset: 1) } label: { Image(systemName: "arrow.down") }.disabled(index + 1 == model.selectedKey.effectiveMacro.count).help("Descendre l’étape")
                        Button { model.removeMacroStep(step.id) } label: { Image(systemName: "xmark") }.help("Retirer l’étape")
                    }.font(.caption).buttonStyle(.borderless)
                    switch step.kind {
                    case .shortcut: ShortcutControls(model: model, step: step)
                    case .text:
                        TextInsertionView(text: Binding(get: { step.text ?? "" }, set: { value in model.updateMacroStep(step.id, deferSave: true) { $0.text = TextInsertion.draft(value) } }))
                    case .wait:
                        HStack {
                            TextField("Durée", value: Binding(get: { step.seconds }, set: { value in
                                model.updateMacroStep(step.id) { $0.seconds = value.isFinite ? min(60, max(0, value)) : 0.5 }
                            }), format: .number).textFieldStyle(.roundedBorder).frame(width: 85)
                            Text("secondes")
                            Stepper("Durée", value: Binding(get: { step.seconds }, set: { value in
                                model.updateMacroStep(step.id) { $0.seconds = min(60, max(0, value)) }
                            }), in: 0...60, step: 0.1).labelsHidden()
                        }.font(.caption)
                    case .website:
                        WebsiteAddressView(address: Binding(get: { step.websiteAddress ?? "" }, set: { value in model.updateMacroStep(step.id, deferSave: true) { $0.websiteAddress = String(value.prefix(4096)) } }))
                    case .application:
                        Text(step.label).font(.caption).lineLimit(2)
                        Button("Choisir l’application…") { model.chooseApplication(step: step.id) }
                    }
                }.padding(12).background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            }
            if model.selectedKey.effectiveMacro.isEmpty { Text("Ajoute du texte, des raccourcis, des pauses et des applications dans l’ordre souhaité.").font(.caption).foregroundStyle(.secondary) }
            Text("Un appui lance les étapes dans l’ordre. Une nouvelle macro remplace celle en cours.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct KeyEditorView: View {
    @ObservedObject var model: DeckModel
    private var key: KeyAssignment { model.selectedKey }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Touche \(model.selected + 1)").font(.title3).fontWeight(.semibold)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Titre").font(.caption).foregroundStyle(.secondary)
                    TextField("Ex. Copier", text: Binding(get: { key.title }, set: { value in model.updateSelected(deferSave: true) { $0.title = String(value.prefix(80)) } }))
                        .textFieldStyle(.roundedBorder)
                    Toggle("Afficher le titre", isOn: Binding(get: { key.showsTitle }, set: { value in model.updateSelected { $0.showTitle = value } }))
                        .font(.caption)
                    Text("Sur le boîtier et dans l’aperçu. Le titre reste enregistré quand il est masqué.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Picker("Action", selection: Binding(get: { key.effectiveKind }, set: { model.changeAction($0) })) {
                    ForEach(KeyActionKind.allCases) { kind in Text(kind.title).tag(kind) }
                }.disabled(model.isHomeNavigationKey)
                switch key.effectiveKind {
                case .shortcut:
                    ShortcutControls(model: model)
                    Picker("Appui", selection: Binding(get: { key.effectivePressMode }, set: { value in model.updateSelected { $0.pressMode = value } })) {
                        ForEach(PressMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                    if key.effectivePressMode == .hold { Text("Le raccourci reste appuyé sous ton doigt, puis se relâche quand tu enlèves le doigt.").font(.caption).foregroundStyle(.secondary) }
                case .macro: MacroEditorView(model: model)
                case .text:
                    TextInsertionView(text: Binding(get: { key.text ?? "" }, set: { value in model.updateSelected(deferSave: true) { $0.text = TextInsertion.draft(value) } }))
                case .application:
                    Text(key.applicationPath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? "Aucune application choisie").font(.caption)
                    Button("Choisir l’application…") { model.chooseApplication() }
                    LaunchPageView(model: model)
                case .website:
                    WebsiteAddressView(address: Binding(get: { key.websiteAddress ?? "" }, set: { value in model.updateSelected(deferSave: true) { $0.websiteAddress = String(value.prefix(4096)) } }))
                    LaunchPageView(model: model)
                case .screenCapture:
                    Picker("Capturer", selection: Binding(get: { key.effectiveCaptureMode }, set: { value in model.updateSelected { $0.captureMode = value } })) {
                        ForEach(ScreenCaptureMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                    Text("Le bouton lance Snapzy directement, même quand cette fenêtre est ouverte.").font(.caption).foregroundStyle(.secondary)
                    Button("Essayer la capture") { model.captureScreen(key.effectiveCaptureMode) }
                case .page:
                    Picker("Page à afficher", selection: Binding(get: { key.targetPageID ?? "" }, set: { value in model.updateSelected { $0.targetPageID = value.isEmpty ? nil : value } })) {
                        Text("Choisir une page").tag("")
                        ForEach(model.configuration.allPages) { page in Text(page.name).tag(page.id) }
                    }.disabled(model.isHomeNavigationKey)
                    Text(model.isHomeNavigationKey ? "Les deux dernières touches restent réservées au retour à l’accueil sur les pages de logiciels ou de sites." : "Un appui sur le boîtier affiche les 15 touches de cette page.").font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                HStack(spacing: 12) {
                    if model.keyPreviews.indices.contains(model.selected) {
                        Image(nsImage: model.keyPreviews[model.selected]).resizable().frame(width: 58, height: 58).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        Button("Choisir une icône…") { model.chooseIcon() }
                        if key.iconPNG != nil { Button("Retirer l’icône") { model.removeIcon() }.font(.caption) }
                    }
                }
                IconAppearanceView(appearance: Binding(get: { key.effectiveAppearance }, set: { value in model.changeAppearance(model.selected) { $0 = value } }), allowZoom: key.iconPNG != nil)
                Text("Les zones transparentes de l’image sont affichées sur noir pur sur le boîtier.").font(.caption).foregroundStyle(.secondary)
                Divider()
                Button("Effacer cette touche", role: .destructive) { model.clear() }.disabled(model.isHomeNavigationKey)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
        }.background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct LaunchPageView: View {
    @ObservedObject var model: DeckModel
    @State private var creatingPage = false
    @State private var pageName = ""
    @State private var sourcePageID = homePageID
    @State private var sourceKeyIndex = 0
    private var key: KeyAssignment { model.selectedKey }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Picker("Afficher aussi une page", selection: Binding(get: { key.launchPageID ?? "" }, set: { value in
                model.setLaunchPage(value.isEmpty ? nil : value)
            })) {
                Text("Aucune · ouvrir seulement").tag("")
                ForEach(model.configuration.allPages) { page in Text(page.name.trimmingCharacters(in: .whitespacesAndNewlines)).tag(page.id) }
            }
            HStack {
                Button("Créer une page…") {
                    model.recording = false
                    sourcePageID = model.activePageID; sourceKeyIndex = model.selected
                    let label = key.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    pageName = !label.isEmpty ? label : key.applicationPath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
                        ?? key.websiteAddress.flatMap(websiteURL)?.host ?? "Nouvelle page"
                    creatingPage = true
                }.disabled((model.configuration.pages ?? []).count >= 50)
                if let pageID = key.launchPageID {
                    Button("Modifier cette page") { model.switchPage(pageID) }
                }
            }
            Text(key.launchPageID == nil ? "Choisis une page si tu veux afficher ses raccourcis quand tu appuies sur cette touche." : "Un appui ouvre le logiciel ou le site, puis affiche les touches de la page choisie. Ce choix est prioritaire sur la page automatique du logiciel.")
                .font(.caption).foregroundStyle(.secondary)
        }.sheet(isPresented: $creatingPage) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Créer une page de raccourcis").font(.title3).fontWeight(.semibold)
                TextField("Nom de la page", text: $pageName).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Nom de la nouvelle page")
                    .onChange(of: pageName) { pageName = String(pageName.prefix(80)) }
                Text("Cette touche ouvrira le logiciel ou le site et affichera la nouvelle page. Tu pourras y ajouter tes raccourcis, macros et liens. Les deux dernières touches reviendront à l’accueil.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Annuler") { creatingPage = false }.keyboardShortcut(.cancelAction)
                    Button("Créer") {
                        model.createLaunchPage(named: pageName, sourcePageID: sourcePageID, keyIndex: sourceKeyIndex)
                        creatingPage = false
                    }.keyboardShortcut(.defaultAction).disabled(pageName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(24).frame(width: 430)
        }
    }
}

struct WebsiteAddressView: View {
    @Binding var address: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            TextField("Ex. https://www.wikipedia.org", text: $address).textFieldStyle(.roundedBorder)
                .accessibilityLabel("Adresse du site Internet")
            Text(address.isEmpty || websiteURL(address) != nil ? "Le site s’ouvrira dans ton navigateur habituel. Tu peux saisir simplement son nom, comme wikipedia.org." : "Saisis une adresse Internet en http ou https.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct TextInsertionView: View {
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Texte à insérer").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8).frame(minHeight: 140, maxHeight: 220)
                .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("Texte à insérer")
            Text("Un appui insère ce texte à l’emplacement du curseur dans le logiciel actif. Accents, emojis et retours à la ligne sont conservés.")
                .font(.caption).foregroundStyle(.secondary)
            Text("\(text.count) / 20 000 caractères").font(.caption).foregroundStyle(.secondary)
        }
    }
}
