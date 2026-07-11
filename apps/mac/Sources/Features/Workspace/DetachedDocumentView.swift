import SwiftUI

struct DetachedDocumentView: View {
    // MARK: Lifecycle

    init(model: AppModel, route: DocumentWindowRoute) {
        self.model = model
        self.route = route
        _reader = State(initialValue: model.makeReaderModel())
    }

    // MARK: Internal

    let model: AppModel
    let route: DocumentWindowRoute

    var body: some View {
        ReaderPane(
            attachment: route.attachment,
            item: model.items.first(where: { $0.id == route.itemID }),
            reader: reader,
            onClose: {
                dismissWindow(value: route)
            },
            onDetach: nil
        )
        .frame(minWidth: 720, minHeight: 560)
        .task {
            reader.open(route.attachment)
        }
        .onDisappear {
            reader.clear()
        }
    }

    // MARK: Private

    @Environment(\.dismissWindow) private var dismissWindow
    @State private var reader: ReaderModel
}
