@testable import Core
import Testing

/// OSのスペルチェッカーに頼らず、決まった英単語だけで判定する
@MainActor
private func makeSegmenter() -> MixedLanguageSegmenter {
    MixedLanguageSegmenter(englishWordChecker: EnglishWordSetChecker(words: [
        "google", "googled", "ogle", "meeting", "want", "to", "go", "the", "park", "is", "ish",
        "apple", "python", "copy", "code", "tomato", "sake", "make", "ken", "thinking", "line",
        "sushi", "like", "mac", "at", "Tanaka", "GitHub", "hello", "world", "de", "no"
    ]))
}

/// 区間を「日本語は小文字のまま、英語は[ ]で囲む」形の文字列にする
@MainActor
private func describe(_ input: String, isFinal: Bool = false, precededByEnglish: Bool = false) -> String {
    let letters = Array(input)
    let segments = makeSegmenter().segment(letters, isFinal: isFinal, precededByEnglish: precededByEnglish)
    return segments.map { segment in
        let text = String(letters[segment.range])
        return segment.language == .english ? "[\(text)]" : text
    }.joined()
}

@MainActor
@Test func mixedLanguageSegmenterKeepsJapaneseOnly() {
    #expect(describe("kensaku") == "kensaku")
    #expect(describe("konnichiha") == "konnichiha")
    #expect(describe("kyouhaiitenkidesune") == "kyouhaiitenkidesune")
    #expect(describe("fairu") == "fairu")
    #expect(describe("gakkou") == "gakkou")
    #expect(describe("nihongo") == "nihongo")
}

@MainActor
@Test func mixedLanguageSegmenterKeepsEnglishWordsReadableAsRomajiJapanese() {
    // ローマ字としても自然に読める語は日本語のまま
    #expect(describe("tomato") == "tomato")
    #expect(describe("sake") == "sake")
    #expect(describe("make") == "make")
    #expect(describe("code") == "code")
}

@MainActor
@Test func mixedLanguageSegmenterFindsEnglishWordInJapaneseSentence() {
    #expect(describe("kyouhagoogledekensaku") == "kyouha[google]dekensaku")
    #expect(describe("ashitanomeetingwotsuika") == "ashitano[meeting]wotsuika")
    #expect(describe("watashihaapplegasuki") == "watashiha[apple]gasuki")
    #expect(describe("pythondekaku") == "[python]dekaku")
}

@MainActor
@Test func mixedLanguageSegmenterFindsEnglishOnly() {
    #expect(describe("python") == "[python]")
    #expect(describe("apple") == "[apple]")
    #expect(describe("thinking") == "[thinking]")
    #expect(describe("helloworld") == "[helloworld]")
}

@MainActor
@Test func mixedLanguageSegmenterWhileTyping() {
    // 打っている途中は、続きを打てば日本語になる子音を日本語として待つ
    #expect(describe("kyouhagoog") == "kyouhagoog")
    // ローマ字として読めなくなったら、英単語の頭を英字にする
    #expect(describe("kyouhagoogl") == "kyouha[googl]")
    #expect(describe("kyouhagoogle") == "kyouha[google]")
    #expect(describe("kyouhagoogled") == "kyouha[googled]")
    #expect(describe("kyouhagooglede") == "kyouha[google]de")
    // 英単語の後に日本語を打てば、日本語に戻る
    #expect(describe("is") == "is")
    #expect(describe("isha") == "isha")
    #expect(describe("want") == "[want]")
    #expect(describe("wanta") == "wanta")
}

@MainActor
@Test func mixedLanguageSegmenterAtFinal() {
    // 確定するときは、末尾の子音は日本語にならない
    #expect(describe("ashitanomeeting", isFinal: false) == "ashitanomeeting")
    #expect(describe("ashitanomeeting", isFinal: true) == "ashitano[meeting]")
    #expect(describe("mac", isFinal: true) == "[mac]")
    // 末尾の n は「ん」
    #expect(describe("ken", isFinal: true) == "ken")
}

@MainActor
@Test func mixedLanguageSegmenterPrefersEnglishAfterEnglishSentence() {
    #expect(describe("to") == "to")
    #expect(describe("to", precededByEnglish: true) == "[to]")
    #expect(describe("go", precededByEnglish: true) == "[go]")
    #expect(describe("sushi", precededByEnglish: true) == "[sushi]")
    // 英単語でなければ日本語
    #expect(describe("kyouha", precededByEnglish: true) == "kyouha")
}

@MainActor
@Test func mixedLanguageSegmenterKeepsUppercaseWordsEnglish() {
    #expect(describe("I") == "[I]")
    #expect(describe("GitHubdekensaku") == "[GitHub]dekensaku")
    #expect(describe("Tanakasan") == "[Tanaka]san")
}

@MainActor
@Test func mixedLanguageSegmenterKeepsUnknownLettersRomaji() {
    // 知らない英字の並びは、今までどおりローマ字入力のまま
    #expect(describe("nginx") == "nginx")
    #expect(describe("kyouhs", isFinal: true) == "kyouhs")
}

/// 固有名詞の辞書も使って区間を表す（同梱の辞書と同じく、固有名詞は小文字で引く）
@MainActor
private func describeWithProperNouns(_ input: String, isFinal: Bool = false) -> String {
    let segmenter = MixedLanguageSegmenter(englishWordChecker: EnglishWordSetChecker(
        words: ["phone", "book", "mac", "de", "no"],
        properNouns: ["iPhone", "Amazon", "Adobe", "Notion", "Siri", "MacBook"]
    ))
    let letters = Array(input)
    return segmenter.segment(letters, isFinal: isFinal).map { segment in
        let text = String(letters[segment.range])
        return segment.language == .english ? "[\(text)]" : text
    }.joined()
}

@MainActor
@Test func mixedLanguageSegmenterFindsLowercaseProperNouns() {
    // スペルチェッカーは iPhone しか認めないが、同梱の辞書では小文字で引ける
    #expect(describeWithProperNouns("iphonewokatta", isFinal: true) == "[iphone]wokatta")
    #expect(describeWithProperNouns("macbookgahoshii", isFinal: true) == "[macbook]gahoshii")
}

@MainActor
@Test func mixedLanguageSegmenterTreatsReadableProperNounsAsEnglish() {
    // ローマ字として読める固有名詞（あまぞん、あどべ）も英語にする
    #expect(describeWithProperNouns("amazon") == "[amazon]")
    #expect(describeWithProperNouns("adobe") == "[adobe]")
    #expect(describeWithProperNouns("kyouhaamazondekaimono") == "kyouha[amazon]dekaimono")
    #expect(describeWithProperNouns("notionnimemosuru") == "[notion]nimemosuru")
    // 打っている途中は日本語のまま
    #expect(describeWithProperNouns("amazo") == "amazo")
}

@MainActor
@Test func mixedLanguageSegmenterKeepsJapaneseAroundProperNouns() {
    // 音節の途中から始まる並び（まどべ の adobe）は固有名詞にしない
    #expect(describeWithProperNouns("madobedeyomu", isFinal: true) == "madobedeyomu")
    // 短い名前（しり）は、ローマ字として読めれば日本語のまま
    #expect(describeWithProperNouns("siri") == "siri")
    #expect(describeWithProperNouns("osiriwoutsu") == "osiriwoutsu")
}
