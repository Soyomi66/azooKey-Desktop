@testable import Core
import KanaKanjiConverterModule
import Testing

/// macOS版のローマ字入力と同じ入力方式
private let romanInputStyle: InputStyle = .mapped(id: .defaultRomanToKana)

@MainActor
private func makeSegmenter() -> MixedLanguageSegmenter {
    MixedLanguageSegmenter(englishWordChecker: EnglishWordSetChecker(words: [
        "google", "googled", "meeting", "want", "apple", "python"
    ]))
}

/// キーを1つずつ押すのと同じように、`.key`の入力を足すたびに判定する
@MainActor
private func type(
    _ text: String,
    into composingText: inout ComposingText,
    runStartIndex: inout Int?,
    segmenter: MixedLanguageSegmenter
) {
    for character in text {
        composingText.insertAtCursorPosition([.init(piece: .key(intention: nil, input: character, modifiers: []), inputStyle: romanInputStyle)])
        let result = MixedLanguageComposer.apply(
            to: composingText,
            runStartIndex: runStartIndex,
            segmenter: segmenter,
            isFinal: false,
            romanInputStyle: romanInputStyle,
            precededByEnglish: false
        )
        composingText = result.composingText
        runStartIndex = result.runStartIndex
    }
}

@MainActor
private func typedComposingText(_ text: String, isFinal: Bool = false) -> ComposingText {
    let segmenter = makeSegmenter()
    var composingText = ComposingText()
    var runStartIndex: Int?
    type(text, into: &composingText, runStartIndex: &runStartIndex, segmenter: segmenter)
    if isFinal {
        composingText = MixedLanguageComposer.apply(
            to: composingText,
            runStartIndex: runStartIndex,
            segmenter: segmenter,
            isFinal: true,
            romanInputStyle: romanInputStyle,
            precededByEnglish: false
        ).composingText
    }
    return composingText
}

@MainActor
private func convertTarget(typing text: String, isFinal: Bool = false) -> String {
    typedComposingText(text, isFinal: isFinal).convertTarget
}

@MainActor
@Test func mixedLanguageComposerConvertsMixedSentence() {
    #expect(convertTarget(typing: "kyouhagoogledekensaku") == "きょうはgoogleでけんさく")
    #expect(convertTarget(typing: "ashitanomeetingwotsuika") == "あしたのmeetingをついか")
    #expect(convertTarget(typing: "watashihaapplegasuki") == "わたしはappleがすき")
}

@MainActor
@Test func mixedLanguageComposerKeepsJapaneseOnly() {
    #expect(convertTarget(typing: "kyouhaiitenkidesune") == "きょうはいいてんきですね")
    #expect(convertTarget(typing: "gakkou") == "がっこう")
}

@MainActor
@Test func mixedLanguageComposerIntermediateState() {
    #expect(convertTarget(typing: "kyouhagoog") == "きょうはごおg")
    #expect(convertTarget(typing: "kyouhagoogl") == "きょうはgoogl")
    #expect(convertTarget(typing: "kyouhagoogle") == "きょうはgoogle")
}

@MainActor
@Test func mixedLanguageComposerAtFinal() {
    #expect(convertTarget(typing: "ashitanomeeting") == "あしたのめえちんg")
    #expect(convertTarget(typing: "ashitanomeeting", isFinal: true) == "あしたのmeeting")
}

@MainActor
@Test func mixedLanguageComposerTurnsNBeforeEnglishIntoN() {
    // 英語の直前の n は「ん」になる
    #expect(convertTarget(typing: "nihonpython") == "にほんpython")
}

@MainActor
@Test func mixedLanguageComposerKeepsTypedPieces() {
    // 入力方式だけを切り替えるので、英数に変換すると打ったとおりの英字が出る
    let composingText = typedComposingText("kyouhagoogledekensaku")
    #expect(composingText.input.map(\.piece).inputString(preferIntention: false) == "kyouhagoogledekensaku")
    #expect(composingText.input.allSatisfy {
        if case .key = $0.piece {
            true
        } else {
            false
        }
    })
}

@MainActor
@Test func mixedLanguageComposerKeepsEnglishAfterDeleteAndRetype() {
    let segmenter = makeSegmenter()
    var composingText = ComposingText()
    var runStartIndex: Int?
    type("kyouhagoogle", into: &composingText, runStartIndex: &runStartIndex, segmenter: segmenter)
    #expect(composingText.convertTarget == "きょうはgoogle")
    // 英字を1文字消して打ち直しても、英語のまま
    composingText.deleteBackwardFromCursorPosition(count: 1)
    #expect(composingText.convertTarget == "きょうはgoogl")
    type("ede", into: &composingText, runStartIndex: &runStartIndex, segmenter: segmenter)
    #expect(composingText.convertTarget == "きょうはgoogleで")
}

@MainActor
@Test func mixedLanguageComposerLeavesTextWhenCursorIsNotAtEnd() {
    let segmenter = makeSegmenter()
    var composingText = ComposingText()
    composingText.insertAtCursorPosition("googleha", inputStyle: romanInputStyle)
    _ = composingText.moveCursorFromCursorPosition(count: -1)
    let result = MixedLanguageComposer.apply(
        to: composingText,
        runStartIndex: nil,
        segmenter: segmenter,
        isFinal: false,
        romanInputStyle: romanInputStyle,
        precededByEnglish: false
    )
    #expect(!result.changed)
    #expect(result.composingText.convertTarget == composingText.convertTarget)
}

@MainActor
@Test func mixedLanguageComposerSupportsOnlyDefaultRomanTable() {
    #expect(MixedLanguageComposer.supports(.roman2kana))
    #expect(MixedLanguageComposer.supports(.mapped(id: .defaultRomanToKana)))
    #expect(!MixedLanguageComposer.supports(.direct))
    #expect(!MixedLanguageComposer.supports(.mapped(id: .defaultAZIK)))
    #expect(!MixedLanguageComposer.supports(.mapped(id: .defaultKanaJIS)))

    // AZIKでは書き換えない
    var composingText = ComposingText()
    composingText.insertAtCursorPosition("google", inputStyle: .mapped(id: .defaultAZIK))
    let result = MixedLanguageComposer.apply(
        to: composingText,
        runStartIndex: nil,
        segmenter: makeSegmenter(),
        isFinal: true,
        romanInputStyle: .mapped(id: .defaultAZIK),
        precededByEnglish: false
    )
    #expect(!result.changed)
}

@MainActor
@Test func mixedLanguageComposerIgnoresKanaInputKeys() {
    // かな入力のように、キーが別の文字を表す入力は英字として扱わない
    #expect(MixedLanguageComposer.letter(of: .init(piece: .key(intention: "ち", input: "a", modifiers: []), inputStyle: romanInputStyle)) == nil)
    #expect(MixedLanguageComposer.letter(of: .init(piece: .key(intention: nil, input: "a", modifiers: []), inputStyle: romanInputStyle)) == "a")
    #expect(MixedLanguageComposer.letter(of: .init(piece: .character("1"), inputStyle: romanInputStyle)) == nil)
}

@MainActor
@Test func mixedLanguageComposerDetectsEnglishSentenceContext() {
    #expect(MixedLanguageComposer.isEnglishSentenceContext("I want "))
    #expect(MixedLanguageComposer.isEnglishSentenceContext("Hello, "))
    // 日本語の文の中の英単語の後ろは、英文の続きとして扱わない
    #expect(!MixedLanguageComposer.isEnglishSentenceContext("今日はgoogle "))
    #expect(!MixedLanguageComposer.isEnglishSentenceContext("I want"))
    #expect(!MixedLanguageComposer.isEnglishSentenceContext("今日は "))
    #expect(!MixedLanguageComposer.isEnglishSentenceContext("2026 "))
    #expect(!MixedLanguageComposer.isEnglishSentenceContext(""))
}

@MainActor
@Test func mixedLanguageComposerKeepsDirectLettersBeforeRun() {
    // 英語入力で打った英字（この機能が切り替えたものではない）は、判定の対象にしない
    let segmenter = makeSegmenter()
    var composingText = ComposingText()
    composingText.insertAtCursorPosition("kyou", inputStyle: .direct)
    var runStartIndex: Int?
    type("ha", into: &composingText, runStartIndex: &runStartIndex, segmenter: segmenter)
    #expect(composingText.convertTarget == "kyouは")
}

@MainActor
@Test func mixedLanguageComposerFindsProperNounSpellings() {
    let checker = EnglishWordSetChecker(words: ["phone"], properNouns: ["iPhone", "GitHub"])
    let segmenter = MixedLanguageSegmenter(englishWordChecker: checker)
    var composingText = ComposingText()
    var runStartIndex: Int?
    type("iphonetogithub", into: &composingText, runStartIndex: &runStartIndex, segmenter: segmenter)
    composingText = MixedLanguageComposer.apply(
        to: composingText,
        runStartIndex: runStartIndex,
        segmenter: segmenter,
        isFinal: true,
        romanInputStyle: romanInputStyle,
        precededByEnglish: false
    ).composingText
    #expect(composingText.convertTarget == "iphoneとgithub")
    #expect(MixedLanguageComposer.properNounSpellings(in: composingText, checker: checker) == ["iphone": "iPhone", "github": "GitHub"])
}

@Test func mixedLanguageComposerReplacesOnlyWholeWords() {
    let spellings = ["iphone": "iPhone"]
    #expect(MixedLanguageComposer.replacingWords(in: "iphoneを買った", spellings: spellings) == "iPhoneを買った")
    #expect(MixedLanguageComposer.replacingWords(in: "新しいiphoneとiphone", spellings: spellings) == "新しいiPhoneとiPhone")
    // 英字の並びの一部は置き換えない
    #expect(MixedLanguageComposer.replacingWords(in: "iphones", spellings: spellings) == "iphones")
}

@Test func mixedLanguageComposerMakesProperNounCandidate() {
    let spellings = ["iphone": "iPhone"]
    let data = [
        DicdataElement(word: "i", ruby: "i", cid: 0, mid: 0, value: 0),
        DicdataElement(word: "phone", ruby: "phone", cid: 0, mid: 0, value: 0),
        DicdataElement(word: "を", ruby: "ヲ", cid: 0, mid: 0, value: 0)
    ]
    let candidate = Candidate(text: "iphoneを", value: 0, composingCount: .inputCount(7), lastMid: 0, data: data)
    let result = MixedLanguageComposer.properNounCandidate(from: candidate, spellings: spellings)
    #expect(result?.text == "iPhoneを")
    // 英字が複数の語に分かれていても、語の区切りを保って正しい表記にする
    #expect(result?.data.map(\.word) == ["i", "Phone", "を"])
    #expect(result?.isLearningTarget == candidate.isLearningTarget)
    // 置き換える語がなければ候補を作らない
    #expect(MixedLanguageComposer.properNounCandidate(from: candidate, spellings: ["github": "GitHub"]) == nil)
}

/// 英字は1文字ずつ別の語にする（ダイレクト入力の英字の変換結果と同じ形）
private func letterElements(_ text: String) -> [DicdataElement] {
    text.map { DicdataElement(word: String($0), ruby: String($0), cid: CIDData.一般名詞.cid, mid: MIDData.一般.mid, value: 0) }
}

@Test func mixedLanguageComposerKeepsEnglishWordInFirstClause() {
    let data = letterElements("python") + [
        DicdataElement(word: "会議", ruby: "カイギ", cid: CIDData.一般名詞.cid, mid: MIDData.一般.mid, value: 0)
    ]
    // 変換器の関数は英字1文字で区切る
    #expect(Candidate.makePrefixClauseCandidate(data: data).text == "p")
    let clause = MixedLanguageComposer.makePrefixClauseCandidate(data: data)
    #expect(clause.text == "python")
    #expect(clause.data.map(\.word).joined() == clause.text)
    #expect(clause.composingCount == .surfaceCount(clause.data.reduce(0) { $0 + $1.ruby.count }))
    // 日本語で始まるときは変換器の関数と同じ
    let japanese = [DicdataElement(word: "今日", ruby: "キョウ", cid: CIDData.一般名詞.cid, mid: MIDData.一般.mid, value: 0)] + letterElements("python")
    #expect(MixedLanguageComposer.makePrefixClauseCandidate(data: japanese).text == Candidate.makePrefixClauseCandidate(data: japanese).text)
}

@Test func mixedLanguageComposerRemovesCandidatesSplittingWord() {
    var composingText = ComposingText()
    composingText.insertAtCursorPosition("python", inputStyle: .direct)
    composingText.insertAtCursorPosition("de", inputStyle: romanInputStyle)
    let split = Candidate(text: "p", value: 0, composingCount: .surfaceCount(1), lastMid: 0, data: letterElements("p"))
    let whole = Candidate(text: "pythonで", value: 0, composingCount: .surfaceCount(7), lastMid: 0, data: letterElements("python"))
    #expect(MixedLanguageComposer.removingCandidatesSplittingWord([split, whole], composingText: composingText).map(\.text) == ["pythonで"])
}
