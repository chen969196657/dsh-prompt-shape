# dsh-prompt-shape

DSH（DeepSeek Harness）插件：把聊天回复的**形态**收敛住。

四层结构，各自独立开关，任何一层挂掉不影响其余。零宿主补丁——不改 `app.asar` 里的任何文件，全部通过 cordis 的服务与事件钩子挂在 profile 上。

| 层 | 作用 | 常驻成本 |
|---|---|---|
| L0 | 提示词内核（薄，2000 tok 级，挂在 `order -100000` 最前） | ~2000 tok |
| L1 | 宿主侧剥离 + 响应修补 + prefill 锚 | 0（按请求触发） |
| L1.5 | 连续空回复换线（`agent/request` 改写 provider/model） | 0 |
| L2 | 原始流镜像 + 会话事件镜像 + 遮蔽快照 + 自我撤回探针 | 0 |
| L3 | 按需片段（runtime skill，平时 0 token，命中才装一片） | 0 |

## 安装

本包不在 npm 上，从源码装。

### 一条命令（不依赖 pnpm，最省事）

```bash
wget -qO- https://raw.githubusercontent.com/chen969196657/dsh-prompt-shape/main/install.sh | sh -s web
```

`sh -s <profile>` 里的 `web` 换成你的 profile 名。脚本会下载、解包、建符号链接、登记 `bundles`，全程不需要 pnpm 联网解析依赖。

下面四种方式按需选。

### 方式 A：从 GitHub 直接装（推荐）

```bash
dsh plugin --profile <profile> add github:chen969196657/dsh-prompt-shape
```

`<profile>` 换成你的 profile 名。桌面版（Electron 管理）的 `desktop` profile 不接受 `dsh plugin`，见方式 C。

然后往该 profile 的 `package.json` 的 `dsh.profile.bundles` 数组里加一行：

```json
"dsh-prompt-shape"
```

### 方式 B：从 tarball 装

```bash
dsh plugin --profile <profile> add https://github.com/chen969196657/dsh-prompt-shape/archive/refs/heads/main.tar.gz
```

装完同样要补 `bundles` 那一行。

### 方式 C：桌面版 desktop profile（Electron 独占）

`desktop` profile 由 Electron App 独占，`dsh plugin --profile desktop` 会被拒（`managed exclusively by the Electron application`）。改 manifest：

```bash
mkdir -p ~/.dsh/plugins
cp -r dsh-prompt-shape ~/.dsh/plugins/

# ~/.dsh/profiles/desktop/package.json 里两处：
#   dependencies:            "dsh-prompt-shape": "link:../../plugins/dsh-prompt-shape"
#   dsh.profile.bundles:     追加 "dsh-prompt-shape"

cd ~/.dsh/profiles/desktop && pnpm install
```

改完**完全退出 App**（托盘退出，不是关窗口）再启动。

### 方式 D：手动 link（任何 profile）

```bash
mkdir -p ~/.dsh/plugins && cp -r dsh-prompt-shape ~/.dsh/plugins/
node -e 'const fs=require("fs"),p=process.env.HOME+"/.dsh/profiles/PROFILE/package.json";const j=JSON.parse(fs.readFileSync(p,"utf8"));j.dependencies=j.dependencies||{};j.dependencies["dsh-prompt-shape"]="link:../../plugins/dsh-prompt-shape";j.dsh=j.dsh||{};j.dsh.profile=j.dsh.profile||{};j.dsh.profile.bundles=j.dsh.profile.bundles||[];if(!j.dsh.profile.bundles.includes("dsh-prompt-shape"))j.dsh.profile.bundles.push("dsh-prompt-shape");fs.writeFileSync(p,JSON.stringify(j,null,2))'
cd ~/.dsh/profiles/PROFILE && pnpm install --config.auto-install-peers=false
```

`link:` 是纯符号链接，不联网、不解析 peer。Android（Termux / proot Ubuntu）上最稳。

## 安装后验证

```bash
ls -l ~/.dsh/profiles/<profile>/node_modules/dsh-prompt-shape
grep -c '"dsh-prompt-shape"' ~/.dsh/profiles/<profile>/package.json   # 期望 2
```

重启 `dsh web` / `dsh tui` 后，会话开头的起手符与末尾回声即为生效标志。

## 配置

全部配置在 [`cordis.patch.yml`](./cordis.patch.yml) 一份里，改完重启生效。常用项：

```yaml
kernel: auto            # 内核强度档
kernelTail: on          # 尾部回声（同一立场在 prompt 最末尾再压一次）
operatorPrompt: on      # 读 $DSH_HOME/prompt-inject.md 注入 system prompt
operatorHome: ''        # 自定义操作稿路径，空 = 默认位置
stripOfficial: true     # 剥离官方注入的重复段
dedupeOperator: foreign # 去重范围：外来的重复注入
msgStrip: true          # 消息级剥离
adapterAlias: deepseek-armor   # 留空 = 关闭请求体整形层
prefill: auto           # auto | native | text | off
prefillText: '已开始输出：'
prefillGraded: on       # 按输出形态选起手符
manyShot: 0             # 0..8，每对约 80 字符
retryOnRefusal: on      # 一次请求内部重试换更强一级起手符
retryMax: 1
leafRouter: auto        # 命中后按需注入片段；off = 不加载
mirror: true            # 原始流镜像到 $DSH_HOME/prompt-shape-raw
shadowSnapshot: true
```

`patches: none` 表示不做任何宿主级补丁，仅用公开服务。

## 命令

```bash
dsh-prompt-shape list                 # 列出镜像过的会话
dsh-prompt-shape recover <sid>        # 从镜像恢复一次原始流
dsh-prompt-shape verify <sid>         # 校验镜像完整性
dsh-prompt-shape cost <文件>          # 估算 token 成本

dsh-shape-doctor --verify             # 检查历史遗留的隐藏会话条目
```

## 目录结构

```
lib/            19 个模块，纯 ESM，无 native 依赖
  index.js      插件入口（apply / inject）
  kernel.js     内核与尾部回声渲染
  operator.js   操作稿读取与合成
  assemble.js   system prompt 组装与去重
  detect.js     回复分类、token 估算、撤回识别
  retry.js      请求内重试环
  leaf.js       按需片段路由
  mirror.js     原始流镜像
  stream.js     llm/stream tee
  route.js      换线
  prestep.js    前置修补
  msgstrip.js   消息级剥离
  toolstrip.js  工具段剥离
  adapter.js    provider 别名代理（请求体整形）
  config.js     配置归一化
skill/          按需片段（runtime skill，不常驻）
bin/            CLI
tools/          词表审计与占位符检查
```

## 环境要求

- Node.js >= 22.15
- DSH 0.2.x（cordis 4）
- `@deepseek-ai/cordis` 作为可选 peer，由宿主提供，无需单独安装

## 许可

MIT
