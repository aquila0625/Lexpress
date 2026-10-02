# Lexpress 快译

Lexpress is a fast, simple English ⇄ Chinese dictionary and translator. Open it, type a word, a sentence or a paragraph, and get the result right away.

Lexpress（快译）是一个简单、直接、高效的中英词典和翻译工具：打开就能输入，单词、句子、整段话都能翻译。

## Status

| Platform | Status |
| --- | --- |
| macOS | Working (`apple/`) |
| iPhone / iPad | In development |
| Android phone / tablet | Planned |

## Features

- Word lookup with UK/US phonetics, multiple meanings, example sentences, phrases and related words
- Sentence and paragraph translation, preferring Apple's on-device translation (free, offline)
- Pronunciation: British and American English, and Chinese
- Image translation: paste or drop an image and the text in it is recognised on device
- macOS: global hotkey `⌥D`, and "translate selection" from the right-click Services menu

## Data sources

Lexpress prefers free and offline sources and only goes online when it has to.

| Source | Used for | Notes |
| --- | --- | --- |
| Apple Translation framework | Sentences and paragraphs | On device, free, works offline once the language model is downloaded |
| Apple Vision | Text recognition in images | On device, images are never uploaded |
| Youdao dictionary JSON endpoint | Word entries | Public but unofficial endpoint; it may change without notice |
| MyMemory | Fallback sentence translation | Free tier, limited daily quota |

Lexpress is not affiliated with any of these providers.

## AI features (bring your own key)

AI features are optional. Lexpress ships with no API key and no server of its own: you register with an AI provider yourself and paste your key into the app. The key stays on your device.

## Build (macOS)

Requires Xcode 16 or later.

```bash
cd apple
./build.sh install
```

This builds `Lexpress.app` and copies it to `/Applications`.

## License

[MIT](LICENSE)
