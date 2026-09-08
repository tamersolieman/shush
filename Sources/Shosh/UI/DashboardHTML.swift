import Foundation

/// Renders the live comparison page. Self-contained, theme-aware, auto-refreshing.
///
/// Styled from the Tamer Solieman Design System's tokens (colors.css / typography.css /
/// spacing.css / effects.css), inlined directly rather than linked — this file ships alone
/// to `~/Library/Application Support/Shosh/dashboard.html` and is opened in the default
/// browser, which can't see fonts registered via `ATSApplicationFontsPath` (that's
/// process-local to the app). Tajawal is embedded as base64 `@font-face` data instead.
enum DashboardHTML {
    static func render(runs: [DictationRun], compareMode: Bool = false, key: String = "Right \u{2325}") -> String {
        let byEngine = Dictionary(grouping: runs, by: \.engine)
        let summary = byEngine
            .map { engine, runs in EngineSummary(engine: engine, runs: runs) }
            .sorted { $0.engine < $1.engine }

        // Comparison groups first — they're the reason this page exists.
        let groups = Dictionary(grouping: runs.filter { $0.group != nil }, by: { $0.group! })
            .sorted { ($0.value.first?.date ?? .distantPast) > ($1.value.first?.date ?? .distantPast) }
        let ungrouped = runs.filter { $0.group == nil }

        let body = runs.isEmpty
            ? emptyState(compareMode: compareMode, key: key)
            : """
              \(groups.isEmpty ? "" : "<h3 class=\"section-title\">Head to head</h3>")
              \(groups.map { comparisonBlock(runs: $0.value) }.joined())
              \(summary.isEmpty ? "" : "<h3 class=\"section-title\">Overall</h3>")
              <div class="grid">\(summary.map(summaryCard).joined())</div>
              \(ungrouped.isEmpty ? "" : runsTable(ungrouped.reversed()))
              """

        return """
        <!doctype html>
        <html lang="en"><head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <!-- The app rewrites this file after every dictation; the page just reloads. -->
        <meta http-equiv="refresh" content="3">
        <title>Shosh — engine comparison</title>
        <style>
        \(fontFaceCSS())
        :root{
          --surface-canvas:#f7f8f9;--surface-card:#ffffff;--border-subtle:#e8ecef;--border-default:#c7d0d6;
          --text-primary:#14181b;--text-secondary:#5a6873;
          --accent-primary:#2e739e;--accent-primary-hover:#235a7d;--accent-secondary:#b97b28;
          --success:#3f9d6d;--danger:#c94f44;
          --radius-md:10px;--radius-lg:16px;--radius-full:999px;
          --ease-standard:cubic-bezier(.4,0,.2,1);
        }
        @media (prefers-color-scheme:dark){:root:not([data-theme="light"]){
          --surface-canvas:#14181b;--surface-card:#1d2328;--border-subtle:#3a444c;--border-default:#5a6873;
          --text-primary:#f7f8f9;--text-secondary:#c7d0d6;
          --accent-primary:#3b8fc4;--accent-primary-hover:#7fbfe0;--accent-secondary:#d99a3e;
        }}
        :root[data-theme="dark"]{
          --surface-canvas:#14181b;--surface-card:#1d2328;--border-subtle:#3a444c;--border-default:#5a6873;
          --text-primary:#f7f8f9;--text-secondary:#c7d0d6;
          --accent-primary:#3b8fc4;--accent-primary-hover:#7fbfe0;--accent-secondary:#d99a3e;
        }
        *{box-sizing:border-box}
        body{margin:0;padding:32px 20px 64px;background:var(--surface-canvas);color:var(--text-primary);
             font-family:'Tajawal',-apple-system,BlinkMacSystemFont,system-ui,sans-serif;font-size:15px;line-height:1.6}
        .wrap{max-width:1120px;margin:0 auto}
        h1{margin:0 0 4px;font-size:28px;font-weight:900;letter-spacing:-.02em}
        .sub{color:var(--text-secondary);font-size:14px;display:flex;align-items:center;gap:8px}
        .bar{display:flex;justify-content:space-between;align-items:center;
             gap:12px;margin-bottom:24px;flex-wrap:wrap}
        .btn{font-size:13px;font-weight:700;text-decoration:none;padding:7px 16px;
             border-radius:var(--radius-full);border:1px solid var(--border-default);color:var(--text-primary);
             background:var(--surface-card);white-space:nowrap;transition:border-color .12s var(--ease-standard),color .12s var(--ease-standard)}
        .btn:hover{border-color:var(--accent-primary);color:var(--accent-primary)}
        .dot{display:inline-block;width:8px;height:8px;border-radius:50%;background:var(--success);
             vertical-align:middle;animation:p 2s infinite}
        @keyframes p{0%,100%{opacity:1}50%{opacity:.35}}
        .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:16px;margin-bottom:32px}
        .card{background:var(--surface-card);border:1px solid var(--border-subtle);border-radius:var(--radius-lg);padding:20px}
        .card h2{margin:0 0 8px;font-size:17px;font-weight:800}
        .card-subtitle{color:var(--text-secondary);font-size:12px;margin-bottom:16px}
        .stats{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}
        .stat{border:1px solid var(--border-subtle);border-radius:var(--radius-md);padding:10px;text-align:center}
        .stat-label{font-size:10px;color:var(--text-secondary);text-transform:uppercase;letter-spacing:.05em;font-weight:700;margin-bottom:6px}
        .stat-value{font-size:19px;font-weight:700;font-variant-numeric:tabular-nums}
        table{width:100%;border-collapse:collapse;font-size:13px}
        .scroll{overflow-x:auto;border:1px solid var(--border-subtle);border-radius:var(--radius-lg);background:var(--surface-card)}
        th{text-align:left;font-size:10px;text-transform:uppercase;letter-spacing:.05em;
           color:var(--text-secondary);font-weight:700;padding:12px 14px;border-bottom:1px solid var(--border-subtle);
           background:var(--surface-canvas)}
        td{padding:11px 14px;border-bottom:1px solid var(--border-subtle);vertical-align:top}
        tr:last-child td{border-bottom:none}
        .num{font-variant-numeric:tabular-nums;white-space:nowrap}
        .pill{font-size:11px;font-weight:700;padding:3px 10px;border-radius:var(--radius-full);white-space:nowrap;
              background:color-mix(in srgb,var(--accent-primary) 16%,transparent);color:var(--accent-primary)}
        .txt{color:var(--text-secondary);max-width:460px}
        .empty{text-align:center;padding:60px 20px}
        .empty .lead{font-size:18px;color:var(--text-primary);font-weight:700;margin-bottom:10px}
        .empty .hint{font-size:13px;color:var(--text-secondary)}
        kbd{background:color-mix(in srgb,var(--text-primary) 10%,transparent);border:1px solid var(--border-default);
            border-radius:6px;padding:2px 8px;font:inherit;font-weight:700}
        footer{margin-top:32px;color:var(--text-secondary);font-size:12px;line-height:1.6}
        .section-title{font-size:13px;text-transform:uppercase;letter-spacing:.06em;color:var(--text-secondary);
             margin:32px 0 16px;font-weight:700}
        .cmp{margin-bottom:16px}
        .cmphead{display:flex;justify-content:space-between;align-items:center;
                 padding-bottom:12px;margin-bottom:16px;border-bottom:1px solid var(--border-subtle);
                 color:var(--text-secondary);font-size:12px}
        .verdict{font-size:11px;font-weight:700;padding:3px 10px;border-radius:var(--radius-full)}
        .verdict.same{background:color-mix(in srgb,var(--success) 16%,transparent);color:var(--success)}
        .verdict.diff{background:color-mix(in srgb,var(--accent-secondary) 16%,transparent);color:var(--accent-secondary)}
        .cols{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:18px}
        .col{min-width:0}
        .colhead{display:flex;align-items:baseline;justify-content:space-between;gap:8px;margin-bottom:4px}
        .big{font-size:20px;font-weight:700;font-variant-numeric:tabular-nums}
        .pill.win{background:color-mix(in srgb,var(--success) 18%,transparent);color:var(--success)}
        .meta{color:var(--text-secondary);font-size:11px;margin-bottom:10px}
        .out{font-size:14px;line-height:1.55;overflow-wrap:anywhere}
        </style></head><body><div class="wrap">
        <h1>Engine comparison</h1>
        <div class="bar">
          <div class="sub"><span class="dot"></span>\(runs.count) dictation\(runs.count == 1 ? "" : "s") recorded — reloads every 3s</div>
          \(runs.isEmpty ? "" : "<a class=\"btn\" href=\"shosh://clear\">Clear results</a>")
        </div>
        \(body)
        <footer>
          Process time is release → text ready: the latency you actually feel. RTF is hold
          duration ÷ process time. Apple streams text while you talk, so its felt latency is
          lower than these numbers suggest; Parakeet resolves everything on release.
        </footer>
        </div></body></html>
        """
    }

    /// Tajawal, embedded as data URIs — the page has to work standalone in a browser, which
    /// can't see the app's `ATSApplicationFontsPath` registration. Only the weights this page
    /// actually sets (400/700/800/900) are read from disk and inlined.
    private static func fontFaceCSS() -> String {
        let weights: [(file: String, weight: Int)] = [
            ("Tajawal-Regular", 400), ("Tajawal-Bold", 700),
            ("Tajawal-ExtraBold", 800), ("Tajawal-Black", 900),
        ]
        let faces = weights.compactMap { file, weight -> String? in
            guard let url = Bundle.main.url(forResource: file, withExtension: "ttf", subdirectory: "Fonts"),
                  let data = try? Data(contentsOf: url) else { return nil }
            let base64 = data.base64EncodedString()
            return """
            @font-face{font-family:'Tajawal';src:url(data:font/ttf;base64,\(base64)) format('truetype');\
            font-weight:\(weight);font-style:normal;font-display:swap}
            """
        }
        return "<style>\(faces.joined())</style>"
    }

    private static func emptyState(compareMode: Bool, key: String) -> String {
        """
        <div class="card empty">
          <p class="lead">Hold <kbd>\(escape(key))</kbd>, say a sentence, let go.</p>
          <p>\(compareMode
              ? "Both engines will run on that one recording and appear here side by side."
              : "Compare mode is off — turn it on in the menu bar to see both engines at once.")</p>
          <p class="hint">Nothing to click here. This page fills in on its own.</p>
        </div>
        """
    }

    /// One recording, every engine's take on it, laid out for direct reading.
    private static func comparisonBlock(runs: [DictationRun]) -> String {
        guard let first = runs.first else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"

        let fastest = runs.min(by: { $0.processSeconds < $1.processSeconds })?.engine

        // Compared on normalized text — case and punctuation differences aren't recognition
        // errors, and Apple auto-punctuates while Parakeet doesn't. Hence "same words"
        // rather than "identical text": the rendered strings can still look different.
        let sameWords = Set(runs.map { normalized($0.text) }).count == 1
        let exact = Set(runs.map(\.text)).count == 1
        let verdict = exact ? "identical" : (sameWords ? "same words" : "words differ")

        let columns = runs.map { run -> String in
            let win = run.engine == fastest && runs.count > 1
            return """
            <div class="col">
              <div class="colhead">
                <span class="pill\(win ? " win" : "")">\(escape(run.engine))\(win ? " · fastest" : "")</span>
                <span class="num big">\(fmt(run.processSeconds, 2))s</span>
              </div>
              <div class="meta">\(fmt(run.realtimeFactor, 0))× realtime · \(run.characters) chars</div>
              <div class="out">\(escape(run.text))</div>
            </div>
            """
        }.joined()

        return """
        <section class="card cmp">
          <div class="cmphead">
            <span class="num">\(formatter.string(from: first.date)) · held \(fmt(first.audioSeconds, 1))s</span>
            <span class="verdict \(sameWords ? "same" : "diff")">\(verdict)</span>
          </div>
          <div class="cols">\(columns)</div>
        </section>
        """
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: " ")
    }

    private struct EngineSummary {
        let engine: String
        let runs: [DictationRun]

        var medianProcess: Double { median(runs.map(\.processSeconds)) }
        var medianRTF: Double { median(runs.map(\.realtimeFactor)) }
        var totalChars: Int { runs.reduce(0) { $0 + $1.characters } }

        /// Median rather than mean — one cold-start outlier shouldn't define the number.
        private func median(_ values: [Double]) -> Double {
            guard !values.isEmpty else { return 0 }
            let sorted = values.sorted()
            let mid = sorted.count / 2
            return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
        }
    }

    private static func summaryCard(_ s: EngineSummary) -> String {
        """
        <section class="card">
          <h2>\(escape(s.engine))</h2>
          <div class="card-subtitle">\(s.runs.count) run\(s.runs.count == 1 ? "" : "s") · median of all</div>
          <div class="stats">
            <div class="stat"><div class="stat-label">Process</div><div class="stat-value">\(fmt(s.medianProcess, 2))s</div></div>
            <div class="stat"><div class="stat-label">RTF</div><div class="stat-value">\(fmt(s.medianRTF, 0))×</div></div>
            <div class="stat"><div class="stat-label">Chars</div><div class="stat-value">\(s.totalChars)</div></div>
          </div>
        </section>
        """
    }

    private static func runsTable(_ runs: [DictationRun]) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"

        let rows = runs.map { run in
            """
            <tr>
              <td class="num">\(formatter.string(from: run.date))</td>
              <td><span class="pill">\(escape(run.engine))</span></td>
              <td class="num">\(fmt(run.audioSeconds, 1))s</td>
              <td class="num">\(fmt(run.processSeconds, 2))s</td>
              <td class="num">\(fmt(run.realtimeFactor, 0))×</td>
              <td class="txt">\(escape(run.text))</td>
            </tr>
            """
        }.joined()

        return """
        <div class="scroll"><table>
          <thead><tr><th>Time</th><th>Engine</th><th>Held</th><th>Process</th><th>RTF</th><th>Transcript</th></tr></thead>
          <tbody>\(rows)</tbody>
        </table></div>
        """
    }

    private static func fmt(_ value: Double, _ places: Int) -> String {
        String(format: "%.\(places)f", value)
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
