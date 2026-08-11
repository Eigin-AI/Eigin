# SwiftStreamingMarkdown

Eigin's markdown renderer (`src/eigin_ios/Sources/Core/Design/Markdown/Rendering`)
is derived from Microsoft's SwiftStreamingMarkdown. The streaming-critical core
(parser, inline/block conversion, and the `ParagraphUIView` streaming engine) was
lifted from commit `5f7c04e0558df6146f90d482edb62cb456986bda` and has since been
modified: trimmed to the blocks Eigin renders, re-themed to Eigin's design tokens,
and adapted for Swift 6.

- **Upstream:** https://github.com/microsoft/SwiftStreamingMarkdown
- **License:** MIT (reproduced in full below)

## License

```
MIT License

Copyright (c) Microsoft Corporation.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE
```
