# SparrowWord

> 一个离线优先、不打断阅读的英语生词工具——查一个词、留住它、之后复习它。

[![最新版本](https://img.shields.io/github/v/release/jackcai-cai/SparrowWord?label=release)](https://github.com/jackcai-cai/SparrowWord/releases/latest)
[![平台 macOS](https://img.shields.io/badge/platform-macOS-111111)](https://github.com/jackcai-cai/SparrowWord/releases/latest)
[![许可证 MIT](https://img.shields.io/github/license/jackcai-cai/SparrowWord)](LICENSE)

[English](README.md) · **中文**

### ⬇️ [下载 macOS 版 — v1.1](https://github.com/jackcai-cai/SparrowWord/releases/latest)

> 未公证版本——首次打开请 **右键 App → 打开 → 打开**(只需一次)。

SparrowWord 是我从头到尾独立做的一个背单词项目:一个**原生 macOS app**、一个 **web 端**,以及它们背后的**词典 API**。它把"词典在一个 app、笔记在另一个、闪卡在第三个"的零散流程,合成一条闭环:**查词 → 收藏 → 复习。**

## 亮点

- 🔎 **离线英文查词,零配置** —— macOS app 内置词典,装好打开就能查"英文 → 中文",无需下载、无需导入。
- 🀄 **离线中文反查英文** —— 输入中文,瞬间给出按词频排序的英文候选,**完全离线(v1.1)**。想要更全的覆盖,之后可再导入 CC-CEDICT。
- ⚡ **快速收藏** —— 几秒钟把一个词连同它的语境、例句、笔记一起存下来。
- 🔁 **间隔重复复习** —— 多种题型,Again / Hard / Good / Easy。
- 🗂️ **个人词库与历史** —— 你查过、留下的一切,都归置好。
- 🧩 **三端一套模型** —— 原生 macOS、web,共享一个 Node.js + SQLite 词典服务。

### 进阶(可选)

导入对应的开放数据集后解锁(见 [词典数据](#词典数据)):

- 🀄 在内置离线反查之上,更全的中英互查覆盖(CC-CEDICT)
- 📚 例句(Tatoeba)与更完整的英文释义(Open English WordNet)
- 🧠 OpenAI 辅助释义(可选;无网时回落到离线)

## 下载(macOS)

**[⬇️ 下载最新版本(v1.1)](https://github.com/jackcai-cai/SparrowWord/releases/latest)**

> 尚未公证——首次打开请 **右键 App → 打开 → 打开**。

## 为什么做它

我主要靠阅读学英语,受够了在词典、笔记、闪卡三个 app 之间来回跳。SparrowWord 就是我希望存在的那个工具——而把它从头到尾(原生 app、web、后端、离线数据)做出来,也是我自学"做出一个真正能用的产品"的方式。

## 技术栈

- **macOS app:** Swift / SwiftUI
- **Web:** Next.js(React, TypeScript)
- **词典 API:** Node.js(Fastify)+ SQLite
- **数据:** ECDICT(打包了精简子集),可选 CC-CEDICT / Tatoeba / Open English WordNet

## 从源码构建

macOS app:

```bash
xcodebuild -project "SparrowWord/SparrowWord.xcodeproj" -scheme SparrowWord -configuration Release build
```

Web + 词典 API:

```bash
npm install
npm run dev    # web 工作区:http://127.0.0.1:3000/workspace
```

## 词典数据

macOS app 内置了一个精简版 **ECDICT** 子集(常用词、它们的变形、常见短语),所以英文查词开箱即用、完全离线。想要更全的中英互查、例句、更完整的英文释义,可在 **设置 → 离线词典** 里导入完整的开放数据集。所有第三方数据各自遵循其许可证——见 [docs/THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md)。

## 路线图

这是第一个公开版本。接下来计划:

- 在线 web 演示(免安装试用)
- 账号 + 多端同步
- 移动端

## 许可证

[MIT](LICENSE)。内置及第三方词典数据遵循 [docs/THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md) 中各自的许可证。

## 作者

由 [Jack Cai](https://github.com/jackcai-cai) 开发。
