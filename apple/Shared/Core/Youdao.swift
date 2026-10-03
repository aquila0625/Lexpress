import Foundation

/// 有道词典的公开 JSON 接口（无需 key，非官方承诺的接口，字段类型不稳定，所以全部按动态 JSON 解析）。
enum Youdao {
    struct Response {
        var entry: WordEntry?
        var suggestions: [Suggestion] = []
    }

    private typealias J = [String: Any]

    static func lookup(_ query: String) async throws -> Response {
        var comps = URLComponents(string: "https://dict.youdao.com/jsonapi")!
        comps.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "le", value: "en")]
        var request = URLRequest(url: comps.url!, timeoutInterval: 6)
        request.setValue("Mozilla/5.0 (Macintosh) QTranslator/1.0", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let root = try JSONSerialization.jsonObject(with: data) as? J else {
            throw URLError(.cannotParseResponse)
        }
        return parse(root, query: query)
    }

    private static func parse(_ d: J, query: String) -> Response {
        var entry = WordEntry(word: query, isChinese: query.containsChinese)

        // 基本释义：英文查询在 ec，中文查询在 ce，结构相同
        let basic = obj(d, "ec") ?? obj(d, "ce")
        if let basic, let w = list(basic, "word").first as? J {
            let head = flatten(obj(obj(w, "return-phrase"), "l")?["i"] ?? w["return-phrase"])
            if !head.isEmpty { entry.word = head }
            if let uk = str(w, "ukphone") { entry.phonetics.append(Phonetic(label: "英", ipa: uk, accent: 1)) }
            if let us = str(w, "usphone") { entry.phonetics.append(Phonetic(label: "美", ipa: us, accent: 2)) }
            entry.pinyin = str(w, "phone")
            for t in list(w, "trs") {
                for tr in list(t as? J, "tr") {
                    guard let l = obj(tr as? J, "l") else { continue }
                    let text = flatten(l["i"])
                    if !text.isEmpty { entry.definitions.append(Definition(text: text, note: str(l, "#tran"))) }
                }
            }
            for f in list(w, "wfs") {
                if let wf = obj(f as? J, "wf"), let name = str(wf, "name"), let value = str(wf, "value") {
                    entry.forms.append("\(name) \(value)")
                }
            }
            entry.tags = list(basic, "exam_type").compactMap { $0 as? String }
        }
        if entry.pinyin == nil, let w = list(obj(d, "simple"), "word").first as? J {
            entry.pinyin = str(w, "phone")
        }

        // 逐条义项：每个意思带自己的词性和例句
        var senses: [Sense] = []
        for w in list(obj(d, "expand_ec"), "word") {
            guard let w = w as? J else { continue }
            let pos = str(w, "pos")
            if pos?.hasPrefix("【") == true { continue }   // 人名、地名
            for t in list(w, "transList") {
                guard let t = t as? J, let meaning = str(t, "trans") else { continue }
                let content = obj(t, "content")
                let examples = list(content, "sents").prefix(2).compactMap { s -> ExamplePair? in
                    guard let s = s as? J, let original = str(s, "sentOrig") else { return nil }
                    return ExamplePair(source: original, translation: str(s, "sentTrans") ?? "",
                                       english: str(s, "sentSpeech") ?? original.strippingTags)
                }
                senses.append(Sense(pos: str(content, "detailPos") ?? pos, meaning: meaning,
                                    isCommon: !list(content, "examType").isEmpty, examples: examples))
            }
        }
        // 接口没有给出每个义项的词频；被标为考试常见义的排在前面，其余保持词典原有顺序
        entry.senses = senses.filter(\.isCommon) + senses.filter { !$0.isCommon }

        // 柯林斯：英文解释 + 例句
        for ce in list(obj(d, "collins"), "collins_entries") {
            for e in list(obj(ce as? J, "entries"), "entry") {
                for te in list(e as? J, "tran_entry") {
                    guard let te = te as? J, let tran = str(te, "tran") else { continue }
                    let pos = obj(te, "pos_entry")
                    let label = [str(pos, "pos"), str(pos, "pos_tips")].compactMap { $0 }.joined(separator: " ")
                    let examples = list(obj(te, "exam_sents"), "sent").compactMap { s -> ExamplePair? in
                        guard let s = s as? J, let en = str(s, "eng_sent") else { return nil }
                        return ExamplePair(source: en, translation: str(s, "chn_sent") ?? "", english: en.strippingTags)
                    }
                    entry.collins.append(CollinsSense(pos: label.isEmpty ? nil : label, explanation: tran, examples: examples))
                }
            }
        }
        entry.collins = Array(entry.collins.prefix(8))

        // 双语例句
        for p in list(obj(d, "blng_sents_part"), "sentence-pair").prefix(5) {
            guard let p = p as? J, let s = str(p, "sentence"), let t = str(p, "sentence-translation") else { continue }
            entry.examples.append(ExamplePair(source: str(p, "sentence-eng") ?? s, translation: t,
                                              english: entry.isChinese ? t : s))
        }

        // 常用词组，没有时退回到网络词组
        for item in list(obj(d, "phrs"), "phrs").prefix(10) {
            guard let phr = obj(item as? J, "phr") else { continue }
            let key = flatten(obj(obj(phr, "headword"), "l")?["i"])
            let value = list(phr, "trs").compactMap { t -> String? in
                let text = flatten(obj(obj(t as? J, "tr"), "l")?["i"])
                return text.isEmpty ? nil : text
            }.joined(separator: "；")
            if !key.isEmpty, !value.isEmpty { entry.phrases.append(Phrase(key: key, value: value)) }
        }
        for item in list(obj(d, "web_trans"), "web-translation") {
            guard let item = item as? J, let key = str(item, "key") else { continue }
            let values = list(item, "trans").compactMap { str($0 as? J, "value") }
            guard !values.isEmpty else { continue }
            if str(item, "@same") == "true" {
                entry.webMeanings = values
            } else if entry.phrases.count < 8, !entry.phrases.contains(where: { $0.key == key }) {
                entry.phrases.append(Phrase(key: key, value: values.joined(separator: "；")))
            }
        }

        // 同根词
        for r in list(obj(d, "rel_word"), "rels") {
            guard let rel = obj(r as? J, "rel") else { continue }
            for w in list(rel, "words") {
                if let w = w as? J, let word = str(w, "word") {
                    entry.related.append(RelatedWord(pos: str(rel, "pos") ?? "", word: word,
                                                     meaning: (str(w, "tran") ?? "").trimmed))
                }
            }
        }

        // 近义词辨析
        for group in list(obj(d, "discriminate"), "data").prefix(3) {
            guard let group = group as? J else { continue }
            let usages = list(group, "usages").compactMap { u -> Phrase? in
                guard let u = u as? J, let word = str(u, "headword"), let usage = str(u, "usage") else { return nil }
                return Phrase(key: word, value: usage)
            }
            guard !usages.isEmpty else { continue }
            let title = str(group, "tran") ?? usages.map(\.key).joined(separator: " / ")
            entry.distinctions.append(Distinction(title: title, usages: usages))
        }

        // 词源
        if let etym = list(obj(obj(d, "etym"), "etyms"), "zh").first as? J {
            entry.etymology = str(etym, "value")
        }

        var response = Response()
        response.entry = entry.hasContent ? entry : nil
        response.suggestions = list(obj(d, "typos"), "typo").compactMap {
            guard let t = $0 as? J, let word = str(t, "word") else { return nil }
            return Suggestion(word: word, meaning: str(t, "trans") ?? "")
        }
        return response
    }

    // MARK: 动态 JSON 取值

    private static func obj(_ d: J?, _ key: String) -> J? { d?[key] as? J }

    private static func str(_ d: J?, _ key: String) -> String? {
        guard let s = d?[key] as? String, !s.trimmed.isEmpty else { return nil }
        return s
    }

    /// 接口里“单个元素”和“数组”会混用，这里统一成数组。
    private static func list(_ d: J?, _ key: String) -> [Any] {
        guard let v = d?[key], !(v is NSNull) else { return [] }
        return v as? [Any] ?? [v]
    }

    /// 把 "字符串 / {#text} / 二者混合的数组" 拼成纯文本。
    private static func flatten(_ value: Any?) -> String {
        switch value {
        case let s as String: return s.trimmed
        case let d as J: return (d["#text"] as? String ?? "").trimmed
        case let a as [Any]:
            return a.map { ($0 as? String) ?? (($0 as? J)?["#text"] as? String) ?? "" }.joined().trimmed
        default: return ""
        }
    }
}
