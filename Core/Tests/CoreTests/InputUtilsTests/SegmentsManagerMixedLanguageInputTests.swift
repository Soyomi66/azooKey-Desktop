import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import Testing

/// macOS版のローマ字入力と同じ入力方式
private let romanInputStyle: InputStyle = .mapped(id: .defaultRomanToKana)

@MainActor
private func makeManager(mixedLanguageRomanInput: Bool) -> SegmentsManager {
    SegmentsManager(
        kanaKanjiConverter: KanaKanjiConverter.withDefaultDictionary(),
        applicationDirectoryURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
        containerURL: nil,
        context: .init(
            useZenzai: false,
            mixedLanguageRomanInput: mixedLanguageRomanInput,
            englishWordChecker: EnglishWordSetChecker(words: ["google", "meeting", "python"])
        )
    )
}

/// キーボードのキーを1つずつ押したときと同じように入力する
@MainActor
private func type(_ text: String, into manager: SegmentsManager, inputStyle: InputStyle = romanInputStyle) {
    for character in text {
        manager.insertAtCursorPosition(pieces: [.key(intention: nil, input: character, modifiers: [])], inputStyle: inputStyle)
    }
}

@MainActor
@Test func segmentsManagerTypesEnglishWordsInRomanInput() {
    let manager = makeManager(mixedLanguageRomanInput: true)
    type("kyouhagoogledekensaku", into: manager)
    #expect(manager.convertTarget == "きょうはgoogleでけんさく")
}

@MainActor
@Test func segmentsManagerKeepsRomanInputWhenMixedLanguageInputIsOff() {
    let manager = makeManager(mixedLanguageRomanInput: false)
    type("kyouhagoogledekensaku", into: manager)
    #expect(manager.convertTarget == "きょうはごおgぇでけんさく")
}

@MainActor
@Test func segmentsManagerKeepsOtherInputTablesUntouched() {
    // AZIKなど、既定のローマ字かな変換表以外では書き換えない
    let enabled = makeManager(mixedLanguageRomanInput: true)
    let disabled = makeManager(mixedLanguageRomanInput: false)
    type("kyouhagoogledekensaku", into: enabled, inputStyle: .mapped(id: .defaultAZIK))
    type("kyouhagoogledekensaku", into: disabled, inputStyle: .mapped(id: .defaultAZIK))
    #expect(enabled.convertTarget == disabled.convertTarget)
    #expect(!enabled.convertTarget.contains("google"))
}

@MainActor
@Test func segmentsManagerJudgesTrailingConsonantBeforeConversion() {
    // 変換のために区切る（スペースキー）前に、末尾の子音も英字として判定し直す
    let manager = makeManager(mixedLanguageRomanInput: true)
    type("ashitanomeeting", into: manager)
    #expect(manager.convertTarget == "あしたのめえちんg")
    manager.insertCompositionSeparator(inputStyle: romanInputStyle)
    #expect(manager.convertTarget == "あしたのmeeting")
}

@MainActor
@Test func segmentsManagerJudgesTrailingConsonantBeforeCommit() {
    // Enterで確定する前に、末尾の子音も英字として判定し直す
    let manager = makeManager(mixedLanguageRomanInput: true)
    type("pythonnomeeting", into: manager)
    #expect(manager.convertTarget == "pythonのめえちんg")
    let committed = manager.commitMarkedText(inputState: .composing)
    #expect(committed.hasSuffix("meeting"))
    #expect(manager.isEmpty)
}

@MainActor
@Test func segmentsManagerStartsNewRunAfterStopComposition() {
    let manager = makeManager(mixedLanguageRomanInput: true)
    type("google", into: manager)
    #expect(manager.convertTarget == "google")
    manager.stopComposition()
    type("gakkou", into: manager)
    #expect(manager.convertTarget == "がっこう")
}

@MainActor
@Test func segmentsManagerOffersProperNounSpelling() {
    // 入力中は打ったとおり（iphone）、変換候補にはその次に正しい表記（iPhone）を出す
    let manager = SegmentsManager(
        kanaKanjiConverter: KanaKanjiConverter.withDefaultDictionary(),
        applicationDirectoryURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
        containerURL: nil,
        context: .init(
            useZenzai: false,
            mixedLanguageRomanInput: true,
            englishWordChecker: EnglishWordSetChecker(words: [], properNouns: ["iPhone"])
        )
    )
    type("iphonewokatta", into: manager)
    #expect(manager.convertTarget == "iphoneをかった")
    manager.update(requestRichCandidates: false)
    guard case .selecting(let candidates, _) = manager.getCurrentCandidateWindow(inputState: .selecting) else {
        Issue.record("変換候補がない")
        return
    }
    let texts = candidates.map(\.text)
    guard let index = texts.firstIndex(where: { $0.hasPrefix("iphone") }) else {
        Issue.record("打ったとおりの候補がない: \(texts)")
        return
    }
    #expect(texts.first?.hasPrefix("iphone") == true)
    // 英単語の頭の1文字だけの候補（i）は出さない
    #expect(!texts.contains("i"))
    #expect(texts[index + 1] == texts[index].replacingOccurrences(of: "iphone", with: "iPhone"))
}

@MainActor
@Test func systemEnglishWordCheckerUsesBuiltInWords() {
    // 同梱の辞書は小文字で引く（OSのスペルチェッカーを使わない環境でも同じ結果になる）
    let checker = SystemEnglishWordChecker()
    #expect(checker.isEnglishWord("iphone"))
    #expect(checker.isEnglishWord("github"))
    #expect(checker.hasEnglishWord(withPrefix: "iph"))
    #expect(checker.properNounSpelling("iphone") == "iPhone")
    #expect(checker.properNounSpelling("macbook") == "MacBook")
    #expect(checker.properNounSpelling("kyouha") == nil)
}

@MainActor
@Test func segmentsManagerKeepsEnglishWordInOneClause() {
    // 英字で始まる入力を変換するとき、英単語の頭の1文字（python の p）だけを最初の文節にしない
    let manager = makeManager(mixedLanguageRomanInput: true)
    type("pythondekaku", into: manager)
    manager.insertCompositionSeparator(inputStyle: romanInputStyle, skipUpdate: true)
    manager.update(requestRichCandidates: true)
    let marked = manager.getCurrentMarkedText(inputState: .selecting).map(\.content)
    #expect(marked.first?.hasPrefix("python") == true, "\(marked)")
}
