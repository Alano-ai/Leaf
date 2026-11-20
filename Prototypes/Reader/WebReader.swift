// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import SwiftUI
import WebKit

struct WebPage: Codable {
    struct Chapter: Codable, Hashable {
        let label: String
        let href: String
    }

    let cfi: String
    let chapter: String
    let fraction: Double
    let textVisible: Bool
    let images: Int
    let fonts: Int
    let scriptPresent: Bool
    let scriptRan: Bool
    let remoteImageLoaded: Bool
    let localFileLoaded: Bool
    let chapters: [Chapter]?
    let fixedLayout: Bool?
    let targetVisible: Bool?
    let kindleVersion: Int?
}

@MainActor
private final class LocalResources: NSObject, WKURLSchemeHandler {
    static let startURL = URL(string: "leaf-probe://reader/index.html")!
    private static let files = [
        "index.html", "reader.js", "foliate/view.js", "foliate/epub.js",
        "foliate/epubcfi.js", "foliate/mobi.js", "foliate/paginator.js",
        "foliate/fixed-layout.js", "foliate/progress.js", "foliate/overlayer.js",
        "foliate/text-walker.js", "foliate/vendor/zip.js", "foliate/vendor/fflate.js",
    ]

    private let resources = Bundle.main.resourceURL!.appending(path: "Web")
    private let file: Data

    init(file: Data) { self.file = file }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, url.scheme == Self.startURL.scheme, url.host == Self.startURL.host,
              url.query == nil, (task.request.httpMethod ?? "GET") == "GET" else {
            task.didFailWithError(URLError(.unsupportedURL))
            return
        }
        let path = String(url.path.dropFirst())
        let data: Data
        let mime: String
        if path == "book" {
            data = file
            mime = "application/octet-stream"
        } else if Self.files.contains(path), let asset = try? Data(contentsOf: resources.appending(path: path)) {
            data = asset
            mime = path == "index.html" ? "text/html; charset=utf-8" : "text/javascript; charset=utf-8"
        } else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let headers = ["Content-Type": mime, "Content-Length": String(data.count),
                       "Access-Control-Allow-Origin": "*", "X-Content-Type-Options": "nosniff"]
        task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)!)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}

@MainActor
final class WebReader: NSObject, WKNavigationDelegate {
    private var navigation: CheckedContinuation<Void, any Error>?
    private var timeout: Task<Void, Never>?
    private(set) var webView: WKWebView!

    init(file: Data) {
        super.init()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.setURLSchemeHandler(LocalResources(file: file), forURLScheme: LocalResources.startURL.scheme!)
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 920, height: 620), configuration: configuration)
        webView.navigationDelegate = self
    }

    func open(format: String) async throws -> WebPage {
        let rules = ["^https?:", "^wss?:", "^ftp:", "^file:"].map {
            #"{"trigger":{"url-filter":"\#($0)"},"action":{"type":"block"}}"#
        }
        guard let ruleList = try await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "LeafReaderProbeOffline", encodedContentRuleList: "[" + rules.joined(separator: ",") + "]"
        ) else { throw ProbeError("WebKit did not install the offline resource rules") }
        webView.configuration.userContentController.add(ruleList)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            navigation = continuation
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(8))
                if !Task.isCancelled { self?.finishNavigation(.failure(ProbeError("WebKit navigation timed out"))) }
            }
            webView.load(URLRequest(url: LocalResources.startURL))
        }
        return try await run("""
            await import(new URL('reader.js', document.baseURI).href)
            return JSON.stringify(await window.reader.open(format))
            """, arguments: ["format": format])
    }

    func run(_ script: String, arguments: [String: String] = [:]) async throws -> WebPage {
        do {
            let result = try await webView.callAsyncJavaScript(script, arguments: arguments,
                                                             in: nil, contentWorld: .page)
            guard let json = result as? String else { throw ProbeError("Missing WebKit page state") }
            return try JSONDecoder().decode(WebPage.self, from: Data(json.utf8))
        } catch {
            let details = (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String
            throw ProbeError(details ?? error.localizedDescription)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let frame = action.targetFrame, let url = action.request.url else { return .cancel }
        if frame.isMainFrame { return url == LocalResources.startURL ? .allow : .cancel }
        return url.scheme == "blob" || url.absoluteString == "about:blank" ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishNavigation(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        finishNavigation(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: any Error) {
        finishNavigation(.failure(error))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finishNavigation(.failure(ProbeError("WebKit content process terminated")))
    }

    private func finishNavigation(_ result: Result<Void, any Error>) {
        timeout?.cancel()
        timeout = nil
        let pending = navigation
        navigation = nil
        pending?.resume(with: result)
    }
}

struct HostView<ViewType: NSView>: NSViewRepresentable {
    let view: ViewType

    func makeNSView(context: Context) -> ViewType { view }
    func updateNSView(_ view: ViewType, context: Context) {}
}
