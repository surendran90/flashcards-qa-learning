import AppKit
import FlashCardsCore
import SwiftUI

// MARK: - Display

extension FormattedText {
    /// Bold runs as an AttributedString for SwiftUI `Text` (bold keeps the surrounding font).
    static func attributed(_ s: String) -> AttributedString {
        guard hasFormatting(s) else { return AttributedString(s) }
        var out = AttributedString()
        for run in runs(s) {
            var piece = AttributedString(run.text)
            if run.bold { piece.inlinePresentationIntent = .stronglyEmphasized }
            out += piece
        }
        return out
    }
}

/// Answer text with its bold runs shown in bold.
struct FormattedAnswer: View {
    let text: String

    var body: some View {
        Text(FormattedText.attributed(text))
    }
}

// MARK: - Editor

/// Lets the formatting toolbar act on the text view's current selection.
@MainActor
final class FormattedEditorController: ObservableObject {
    weak var textView: NSTextView?
    var baseFont: NSFont = .systemFont(ofSize: 13)

    // MARK: Bold

    func toggleBold() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = tv.selectedRange()
        guard range.length > 0 else {
            // No selection: switch the typing style.
            let current = (tv.typingAttributes[.font] as? NSFont) ?? baseFont
            tv.typingAttributes[.font] = isBold(current) ? unbold(current) : bold(current)
            return
        }
        var allBold = true
        storage.enumerateAttribute(.font, in: range) { value, _, stop in
            if !isBold((value as? NSFont) ?? baseFont) { allBold = false; stop.pointee = true }
        }
        guard tv.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, sub, _ in
            let font = (value as? NSFont) ?? baseFont
            storage.addAttribute(.font, value: allBold ? unbold(font) : bold(font), range: sub)
        }
        storage.endEditing()
        tv.didChangeText()
    }

    private func isBold(_ f: NSFont) -> Bool { f.fontDescriptor.symbolicTraits.contains(.bold) }
    private func bold(_ f: NSFont) -> NSFont { NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask) }
    private func unbold(_ f: NSFont) -> NSFont { NSFontManager.shared.convert(f, toNotHaveTrait: .boldFontMask) }

    // MARK: Lists

    func toggleBullets() { transformLines(prefix: { _ in "• " }, matches: Self.isBullet) }
    func toggleNumbers() { transformLines(prefix: { "\($0 + 1). " }, matches: Self.isNumbered) }

    static func isBullet(_ line: String) -> Bool { line.hasPrefix("• ") }
    static func isNumbered(_ line: String) -> Bool {
        let digits = line.prefix { $0.isNumber }
        return !digits.isEmpty && line.dropFirst(digits.count).hasPrefix(". ")
    }

    static func stripListPrefix(_ line: String) -> String {
        if isBullet(line) { return String(line.dropFirst(2)) }
        if isNumbered(line) {
            let digits = line.prefix { $0.isNumber }
            return String(line.dropFirst(digits.count + 2))
        }
        return line
    }

    /// Adds (or, if every selected line already has it, removes) a list prefix on the selected lines.
    private func transformLines(prefix: (Int) -> String, matches: (String) -> Bool) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let ns = storage.string as NSString
        let lineRange = ns.lineRange(for: tv.selectedRange())
        let lines = ns.substring(with: lineRange).components(separatedBy: "\n")
        let hasTrailingNewline = lines.last == ""
        let content = hasTrailingNewline ? Array(lines.dropLast()) : lines
        let nonEmpty = content.filter { !$0.isEmpty }
        let removing = !nonEmpty.isEmpty && nonEmpty.allSatisfy(matches)

        // Edit each line from the end so earlier ranges stay valid; keep bold on the text.
        guard tv.shouldChangeText(in: lineRange, replacementString: nil) else { return }
        storage.beginEditing()
        var lineStart = lineRange.location
        var starts: [Int] = []
        for line in content {
            starts.append(lineStart)
            lineStart += (line as NSString).length + 1
        }
        var number = content.filter { !$0.isEmpty }.count
        for (i, line) in content.enumerated().reversed() where !line.isEmpty {
            number -= 1
            let existing = (line as NSString).length - (Self.stripListPrefix(line) as NSString).length
            let replaceRange = NSRange(location: starts[i], length: existing)
            let attrs = storage.attributes(at: min(starts[i] + existing, max(0, storage.length - 1)), effectiveRange: nil)
            let newPrefix = removing ? "" : prefix(number)
            storage.replaceCharacters(in: replaceRange, with: NSAttributedString(string: newPrefix, attributes: plainAttributes(from: attrs)))
        }
        storage.endEditing()
        tv.didChangeText()
    }

    private func plainAttributes(from attrs: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var a = attrs
        if let f = a[.font] as? NSFont { a[.font] = unbold(f) }
        return a
    }
}

/// A multi-line editor that shows bold as real bold, backed by `FormattedText` marked text.
struct FormattedTextEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    @ObservedObject var controller: FormattedEditorController

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.delegate = context.coordinator
        tv.isRichText = true
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.textContainerInset = NSSize(width: 4, height: 6)
        tv.font = font
        tv.textColor = .labelColor
        tv.typingAttributes = [.font: font, .foregroundColor: NSColor.labelColor]
        tv.textStorage?.setAttributedString(attributed(text))
        controller.textView = tv
        controller.baseFont = font
        context.coordinator.lastText = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        controller.textView = tv
        controller.baseFont = font
        if text != context.coordinator.lastText {
            context.coordinator.lastText = text
            tv.textStorage?.setAttributedString(attributed(text))
        }
    }

    func attributed(_ marked: String) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let boldFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        for run in FormattedText.runs(marked) {
            out.append(NSAttributedString(string: run.text, attributes: [
                .font: run.bold ? boldFont : font, .foregroundColor: NSColor.labelColor]))
        }
        return out
    }

    static func marked(from storage: NSAttributedString) -> String {
        var runs: [FormattedText.Run] = []
        storage.enumerateAttribute(.font, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            let bold = (value as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
            runs.append(FormattedText.Run((storage.string as NSString).substring(with: range), bold: bold))
        }
        return FormattedText.marked(runs)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: FormattedTextEditor
        var lastText = ""

        init(_ parent: FormattedTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView, let storage = tv.textStorage else { return }
            let marked = FormattedTextEditor.marked(from: storage)
            lastText = marked
            parent.text = marked
        }
    }
}

/// Bold / bullet list / numbered list buttons for a `FormattedTextEditor`.
struct FormattingToolbar: View {
    @ObservedObject var controller: FormattedEditorController

    var body: some View {
        HStack(spacing: 4) {
            button("bold", "Bold (⌘B)") { controller.toggleBold() }
                .keyboardShortcut("b", modifiers: .command)
            button("list.bullet", "Bulleted list") { controller.toggleBullets() }
            button("list.number", "Numbered list") { controller.toggleNumbers() }
        }
    }

    private func button(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 22)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.border))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Editor + toolbar used for answers everywhere.
struct AnswerEditor: View {
    @Binding var text: String
    let topic: String
    var minHeight: CGFloat = 140
    @StateObject private var controller = FormattedEditorController()

    private var nsFont: NSFont {
        Theme.isCode(topic) ? .monospacedSystemFont(ofSize: 12, weight: .regular) : .systemFont(ofSize: 13)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FormattingToolbar(controller: controller)
            FormattedTextEditor(text: $text, font: nsFont, controller: controller)
                .frame(minHeight: minHeight)
                .padding(4)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
        }
    }
}
