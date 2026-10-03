package com.yishulabs.qtranslator.core

import org.json.JSONArray
import org.json.JSONObject

/** 有道词典的公开 JSON 接口（无需 key，非官方承诺的接口，字段类型不稳定，所以全部按动态 JSON 解析）。 */
object Youdao {
    class Response(val entry: WordEntry?, val suggestions: List<Suggestion>)

    suspend fun lookup(query: String): Response {
        val url = "https://dict.youdao.com/jsonapi?" + Http.query("q" to query, "le" to "en")
        val response = Http.get(url, timeoutMs = 6_000, headers = mapOf("User-Agent" to "Mozilla/5.0 (Android) QTranslator/1.0"))
        return parse(JSONObject(response.body), query)
    }

    private fun parse(d: JSONObject, query: String): Response {
        var word = query
        val phonetics = mutableListOf<Phonetic>()
        var pinyin: String? = null
        val definitions = mutableListOf<Definition>()
        val forms = mutableListOf<String>()
        var tags = emptyList<String>()

        // 基本释义：英文查询在 ec，中文查询在 ce，结构相同
        val basic = obj(d, "ec") ?: obj(d, "ce")
        val w = list(basic, "word").firstOrNull() as? JSONObject
        if (basic != null && w != null) {
            val head = flatten(obj(obj(w, "return-phrase"), "l")?.opt("i") ?: w.opt("return-phrase"))
            if (head.isNotEmpty()) word = head
            str(w, "ukphone")?.let { phonetics += Phonetic("英", it, 1) }
            str(w, "usphone")?.let { phonetics += Phonetic("美", it, 2) }
            pinyin = str(w, "phone")
            for (t in list(w, "trs")) {
                for (tr in list(t as? JSONObject, "tr")) {
                    val l = obj(tr as? JSONObject, "l") ?: continue
                    val text = flatten(l.opt("i"))
                    if (text.isNotEmpty()) definitions += Definition(text, str(l, "#tran"))
                }
            }
            for (f in list(w, "wfs")) {
                val wf = obj(f as? JSONObject, "wf") ?: continue
                val name = str(wf, "name") ?: continue
                val value = str(wf, "value") ?: continue
                forms += "$name $value"
            }
            tags = list(basic, "exam_type").mapNotNull { it as? String }
        }
        if (pinyin == null) {
            (list(obj(d, "simple"), "word").firstOrNull() as? JSONObject)?.let { pinyin = str(it, "phone") }
        }

        // 逐条义项：每个意思带自己的词性和例句
        val senses = mutableListOf<Sense>()
        for (item in list(obj(d, "expand_ec"), "word")) {
            val ew = item as? JSONObject ?: continue
            val pos = str(ew, "pos")
            if (pos?.startsWith("【") == true) continue   // 人名、地名
            for (t in list(ew, "transList")) {
                val tj = t as? JSONObject ?: continue
                val meaning = str(tj, "trans") ?: continue
                val content = obj(tj, "content")
                val examples = list(content, "sents").take(2).mapNotNull { s ->
                    val sj = s as? JSONObject ?: return@mapNotNull null
                    val original = str(sj, "sentOrig") ?: return@mapNotNull null
                    ExamplePair(original, str(sj, "sentTrans") ?: "", str(sj, "sentSpeech") ?: original.strippingTags)
                }
                senses += Sense(str(content, "detailPos") ?: pos, meaning, list(content, "examType").isNotEmpty(), examples)
            }
        }
        // 接口没有给出每个义项的词频；被标为考试常见义的排在前面，其余保持词典原有顺序
        val sortedSenses = senses.filter { it.isCommon } + senses.filter { !it.isCommon }

        // 柯林斯：英文解释 + 例句
        val collins = mutableListOf<CollinsSense>()
        for (ce in list(obj(d, "collins"), "collins_entries")) {
            for (e in list(obj(ce as? JSONObject, "entries"), "entry")) {
                for (te in list(e as? JSONObject, "tran_entry")) {
                    val tj = te as? JSONObject ?: continue
                    val tran = str(tj, "tran") ?: continue
                    val posEntry = obj(tj, "pos_entry")
                    val label = listOfNotNull(str(posEntry, "pos"), str(posEntry, "pos_tips")).joinToString(" ")
                    val examples = list(obj(tj, "exam_sents"), "sent").mapNotNull { s ->
                        val sj = s as? JSONObject ?: return@mapNotNull null
                        val en = str(sj, "eng_sent") ?: return@mapNotNull null
                        ExamplePair(en, str(sj, "chn_sent") ?: "", en.strippingTags)
                    }
                    collins += CollinsSense(label.ifEmpty { null }, tran, examples)
                }
            }
        }

        // 双语例句
        val isChinese = query.containsChinese
        val examples = list(obj(d, "blng_sents_part"), "sentence-pair").take(5).mapNotNull { p ->
            val pj = p as? JSONObject ?: return@mapNotNull null
            val s = str(pj, "sentence") ?: return@mapNotNull null
            val t = str(pj, "sentence-translation") ?: return@mapNotNull null
            ExamplePair(str(pj, "sentence-eng") ?: s, t, if (isChinese) t else s)
        }

        // 常用词组，没有时退回到网络词组
        val phrases = mutableListOf<Phrase>()
        for (item in list(obj(d, "phrs"), "phrs").take(10)) {
            val phr = obj(item as? JSONObject, "phr") ?: continue
            val key = flatten(obj(obj(phr, "headword"), "l")?.opt("i"))
            val value = list(phr, "trs").mapNotNull { t ->
                flatten(obj(obj(t as? JSONObject, "tr"), "l")?.opt("i")).ifEmpty { null }
            }.joinToString("；")
            if (key.isNotEmpty() && value.isNotEmpty()) phrases += Phrase(key, value)
        }
        var webMeanings = emptyList<String>()
        for (item in list(obj(d, "web_trans"), "web-translation")) {
            val ij = item as? JSONObject ?: continue
            val key = str(ij, "key") ?: continue
            val values = list(ij, "trans").mapNotNull { str(it as? JSONObject, "value") }
            if (values.isEmpty()) continue
            if (str(ij, "@same") == "true") {
                webMeanings = values
            } else if (phrases.size < 8 && phrases.none { it.key == key }) {
                phrases += Phrase(key, values.joinToString("；"))
            }
        }

        // 同根词
        val related = mutableListOf<RelatedWord>()
        for (r in list(obj(d, "rel_word"), "rels")) {
            val rel = obj(r as? JSONObject, "rel") ?: continue
            for (rw in list(rel, "words")) {
                val rj = rw as? JSONObject ?: continue
                val relatedWord = str(rj, "word") ?: continue
                related += RelatedWord(str(rel, "pos") ?: "", relatedWord, (str(rj, "tran") ?: "").trim())
            }
        }

        // 近义词辨析
        val distinctions = mutableListOf<Distinction>()
        for (group in list(obj(d, "discriminate"), "data").take(3)) {
            val gj = group as? JSONObject ?: continue
            val usages = list(gj, "usages").mapNotNull { u ->
                val uj = u as? JSONObject ?: return@mapNotNull null
                val headword = str(uj, "headword") ?: return@mapNotNull null
                val usage = str(uj, "usage") ?: return@mapNotNull null
                Phrase(headword, usage)
            }
            if (usages.isEmpty()) continue
            distinctions += Distinction(str(gj, "tran") ?: usages.joinToString(" / ") { it.key }, usages)
        }

        // 词源
        val etymology = (list(obj(obj(d, "etym"), "etyms"), "zh").firstOrNull() as? JSONObject)?.let { str(it, "value") }

        val entry = WordEntry(
            word = word, isChinese = isChinese, phonetics = phonetics, pinyin = pinyin, tags = tags,
            definitions = definitions, senses = sortedSenses, forms = forms, collins = collins.take(8),
            examples = examples, webMeanings = webMeanings, phrases = phrases, related = related,
            distinctions = distinctions, etymology = etymology,
        )
        val suggestions = list(obj(d, "typos"), "typo").mapNotNull { t ->
            val tj = t as? JSONObject ?: return@mapNotNull null
            val suggested = str(tj, "word") ?: return@mapNotNull null
            Suggestion(suggested, str(tj, "trans") ?: "")
        }
        return Response(if (entry.hasContent) entry else null, suggestions)
    }

    // 动态 JSON 取值

    private fun obj(d: JSONObject?, key: String): JSONObject? = d?.opt(key) as? JSONObject

    private fun str(d: JSONObject?, key: String): String? {
        val s = d?.opt(key) as? String ?: return null
        return s.ifBlank { null }
    }

    /** 接口里“单个元素”和“数组”会混用，这里统一成列表。 */
    private fun list(d: JSONObject?, key: String): List<Any> {
        val v = d?.opt(key) ?: return emptyList()
        if (v == JSONObject.NULL) return emptyList()
        return if (v is JSONArray) List(v.length()) { v.get(it) } else listOf(v)
    }

    /** 把 "字符串 / {#text} / 二者混合的数组" 拼成纯文本。 */
    private fun flatten(value: Any?): String = when (value) {
        is String -> value.trim()
        is JSONObject -> (value.opt("#text") as? String ?: "").trim()
        is JSONArray -> List(value.length()) { value.get(it) }.joinToString("") {
            (it as? String) ?: ((it as? JSONObject)?.opt("#text") as? String) ?: ""
        }.trim()
        else -> ""
    }
}
