#if canImport(UIKit)
import SwiftUI
import UIKit
import PhoebusCore

/// The Search tab field's magnifier becomes the engine picker (Reborn #1260):
/// a tap or hold offers "Search With: Reddit / Google", a small chevron beside
/// it says it's a menu, and Google mode shows a plain capital G in the
/// magnifier's colour. The field is SwiftUI's `.searchable`, so the probe
/// finds its `UISearchBar` through the screen's navigation item and swaps the
/// field's left view.
struct SearchEngineMagnifier: UIViewRepresentable {
    let engine: SearchEngine
    let onChange: (SearchEngine) -> Void

    func makeUIView(context: Context) -> ProbeView { ProbeView() }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.engine = engine
        view.onChange = onChange
        view.install()
    }

    final class ProbeView: UIView {
        var engine: SearchEngine = .reddit
        var onChange: (SearchEngine) -> Void = { _ in }

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { fatalError() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // The search controller is attached after this view appears.
            DispatchQueue.main.async { [weak self] in self?.install() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.install() }
        }

        func install() {
            guard window != nil else { return }
            var controller = owningViewController()
            var field: UISearchTextField?
            while let current = controller, field == nil {
                field = current.navigationItem.searchController?.searchBar.searchTextField
                controller = current.parent
            }
            guard let field else { return }
            let button = (field.leftView as? EngineButton) ?? EngineButton()
            button.configure(engine: engine) { [weak self] picked in self?.onChange(picked) }
            if field.leftView !== button {
                field.leftView = button
                field.leftViewMode = .always
            }
        }
    }

    final class EngineButton: UIButton {
        func configure(engine: SearchEngine, onPick: @escaping (SearchEngine) -> Void) {
            var config = UIButton.Configuration.plain()
            config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 2)
            config.imagePadding = 2
            config.imagePlacement = .trailing
            config.baseForegroundColor = .secondaryLabel
            config.image = UIImage(systemName: "chevron.down",
                                   withConfiguration: UIImage.SymbolConfiguration(pointSize: 8, weight: .bold))
            if engine == .google {
                var title = AttributedString("G")
                title.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
                config.attributedTitle = title
            } else {
                // Magnifier plus chevron, drawn as one image.
                config.attributedTitle = nil
                config.image = Self.magnifierWithChevron()
            }
            self.configuration = config
            accessibilityLabel = "Search With"
            accessibilityValue = engine.title
            accessibilityHint = "Choose whether to search with Reddit or Google."
            accessibilityIdentifier = "search.engine"
            showsMenuAsPrimaryAction = true
            menu = UIMenu(title: "Search With", children: SearchEngine.allCases.map { option in
                let action = UIAction(title: option.title,
                                      image: UIImage(systemName: option == .reddit ? "magnifyingglass" : "g.circle")) { _ in
                    onPick(option)
                }
                action.subtitle = option.subtitle
                action.state = option == engine ? .on : .off
                return action
            })
            sizeToFit()
        }

        private static func magnifierWithChevron() -> UIImage? {
            let glass = UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium))
            let chevron = UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 8, weight: .bold))
            guard let glass, let chevron else { return glass }
            let size = CGSize(width: glass.size.width + 3 + chevron.size.width, height: max(glass.size.height, chevron.size.height))
            return UIGraphicsImageRenderer(size: size).image { _ in
                glass.withTintColor(.secondaryLabel).draw(at: CGPoint(x: 0, y: (size.height - glass.size.height) / 2))
                chevron.withTintColor(.secondaryLabel).draw(at: CGPoint(x: glass.size.width + 3, y: (size.height - chevron.size.height) / 2 + 2))
            }.withRenderingMode(.alwaysOriginal)
        }
    }
}
#endif
