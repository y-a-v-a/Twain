import Textual

/// Textual syntax extensions every Twain parse enables — document windows, print/PDF export
/// and the Quick Look preview alike, so the three renderings can't drift apart.
///
/// `.math` renders `$…$` / `$$…$$` and ```` ```math ```` blocks with SwiftUIMath, whose fonts
/// load from `SwiftUIMath_SwiftUIMath.bundle` via `Bundle.module` — build.sh must copy that
/// bundle into both the app and the appex, or the first formula crashes the process.
public var twainSyntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension] { [.math] }
