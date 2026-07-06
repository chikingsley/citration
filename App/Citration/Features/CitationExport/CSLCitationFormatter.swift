import CitrationCore
import Foundation
import JavaScriptCore

/// CSL-compliant citation formatting via citeproc-js (the processor
/// Zotero uses) running in JavaScriptCore. Styles and locales are
/// bundled CSL XML; items travel as the exporter's CSL JSON.
actor CSLCitationFormatter: CitationFormattingEngine {
    // MARK: Lifecycle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    // MARK: Internal

    func formatCluster(
        _ cluster: CitationCluster,
        items: [BCItem],
        style: CitationStyle,
        options: CitationRenderOptions
    ) throws -> FormattedCitationCluster {
        guard !cluster.items.isEmpty else {
            throw CitationEngineError.invalidInput("cluster must contain at least one citation item")
        }

        let citationItems = cluster.items.map { item -> [String: Any] in
            var payload: [String: Any] = ["id": item.itemID.uuidString]
            if let locator = item.locator?.bcTrimmedNonEmpty {
                payload["locator"] = locator
            }
            if let prefix = item.prefix?.bcTrimmedNonEmpty {
                payload["prefix"] = prefix
            }
            if let suffix = item.suffix?.bcTrimmedNonEmpty {
                payload["suffix"] = suffix
            }
            if item.suppressAuthor {
                payload["suppress-author"] = true
            }
            return payload
        }
        let citationItemsData = try JSONSerialization.data(withJSONObject: citationItems)
        guard let citationItemsJSON = String(data: citationItemsData, encoding: .utf8) else {
            throw CitationEngineError.invalidInput("citation items must serialize to UTF-8 JSON")
        }

        let result = try invoke(
            method: "makeCitation",
            items: items,
            style: style,
            options: options,
            extraArguments: [citationItemsJSON]
        )

        guard let text = result.toString(), !text.isEmpty, text != "undefined" else {
            throw CitationEngineError.invalidInput("citeproc returned no citation text")
        }
        return FormattedCitationCluster(clusterID: cluster.id, text: text, format: options.format)
    }

    func formatBibliography(
        items: [BCItem],
        style: CitationStyle,
        options: CitationRenderOptions
    ) throws -> FormattedBibliography {
        guard !items.isEmpty else {
            return FormattedBibliography(entries: [], format: options.format)
        }

        let result = try invoke(
            method: "makeBibliography",
            items: items,
            style: style,
            options: options,
            extraArguments: []
        )

        guard let entries = result.toArray() as? [String] else {
            throw CitationEngineError.invalidInput("citeproc returned no bibliography entries")
        }

        let trimmed = entries
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return FormattedBibliography(entries: trimmed, format: options.format)
    }

    // MARK: Private

    private static let bootstrapScript = """
    var CitrationCSL = {
        makeEngine: function (itemsJSON, styleXML, localeXML, format) {
            var itemsByID = {};
            JSON.parse(itemsJSON).forEach(function (item) {
                itemsByID[item.id] = item;
            });
            var sys = {
                retrieveLocale: function (lang) { return localeXML; },
                retrieveItem: function (id) { return itemsByID[id]; }
            };
            var engine = new CSL.Engine(sys, styleXML);
            engine.setOutputFormat(format);
            engine.updateItems(Object.keys(itemsByID));
            return engine;
        },
        makeBibliography: function (itemsJSON, styleXML, localeXML, format) {
            var engine = this.makeEngine(itemsJSON, styleXML, localeXML, format);
            var result = engine.makeBibliography();
            return result ? result[1] : [];
        },
        makeCitation: function (itemsJSON, styleXML, localeXML, format, citationItemsJSON) {
            var engine = this.makeEngine(itemsJSON, styleXML, localeXML, format);
            var citation = {
                citationItems: JSON.parse(citationItemsJSON),
                properties: { noteIndex: 0 }
            };
            return engine.previewCitationCluster(citation, [], [], format);
        }
    };
    """

    private let bundle: Bundle
    private var cachedContext: JSContext?
    private var cachedLocaleXML: String?

    private func invoke(
        method: String,
        items: [BCItem],
        style: CitationStyle,
        options: CitationRenderOptions,
        extraArguments: [String]
    ) throws -> JSValue {
        let context = try loadContext()
        let itemsJSON = try CitationExporter().cslJSON(for: items)
        let styleXML = try styleXML(for: style)
        let localeXML = try localeXML()
        let format = jsOutputFormat(for: options.format)

        guard let namespace = context.objectForKeyedSubscript("CitrationCSL") else {
            throw CitationEngineError.invalidInput("citeproc bootstrap missing")
        }

        let arguments: [Any] = [itemsJSON, styleXML, localeXML, format] + extraArguments
        guard let result = namespace.invokeMethod(method, withArguments: arguments) else {
            throw CitationEngineError.invalidInput("citeproc \(method) returned nothing")
        }
        if let exception = context.exception {
            context.exception = nil
            throw CitationEngineError.invalidInput("citeproc error: \(exception)")
        }
        return result
    }

    private func loadContext() throws -> JSContext {
        if let cachedContext {
            return cachedContext
        }

        guard let context = JSContext() else {
            throw CitationEngineError.invalidInput("JavaScriptCore context unavailable")
        }
        guard
            let citeprocURL = bundle.url(forResource: "citeproc", withExtension: "js"),
            let citeprocSource = try? String(contentsOf: citeprocURL, encoding: .utf8)
        else {
            throw CitationEngineError.invalidInput("citeproc.js is not bundled")
        }

        context.evaluateScript(citeprocSource)
        context.evaluateScript(Self.bootstrapScript)
        if let exception = context.exception {
            throw CitationEngineError.invalidInput("citeproc failed to load: \(exception)")
        }

        cachedContext = context
        return context
    }

    private func styleXML(for style: CitationStyle) throws -> String {
        guard
            let styleURL = bundle.url(forResource: style.id, withExtension: "csl"),
            let xml = try? String(contentsOf: styleURL, encoding: .utf8)
        else {
            throw CitationEngineError.invalidInput("Unknown citation style: \(style.id)")
        }
        return xml
    }

    private func localeXML() throws -> String {
        if let cachedLocaleXML {
            return cachedLocaleXML
        }
        guard
            let localeURL = bundle.url(forResource: "locales-en-US", withExtension: "xml"),
            let xml = try? String(contentsOf: localeURL, encoding: .utf8)
        else {
            throw CitationEngineError.invalidInput("CSL locale is not bundled")
        }
        cachedLocaleXML = xml
        return xml
    }

    private func jsOutputFormat(for format: CitationOutputFormat) -> String {
        switch format {
        case .plainText,
             .markdown:
            "text"
        case .html:
            "html"
        }
    }
}
