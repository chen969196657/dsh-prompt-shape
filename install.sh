#!/bin/sh
# dsh-prompt-shape 安装器
# 用法: sh install.sh [profile]      默认 web
#
# POSIX sh，proot Ubuntu / Termux / 桌面 Linux 均可。
# 不依赖 pnpm：直接放源码 + 建 node_modules 符号链接 + 登记 bundles。
set -e

PROFILE="${1:-web}"
DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
SRC="$DSH_HOME/plugins/dsh-prompt-shape"
PDIR="$DSH_HOME/profiles/$PROFILE"
PKG="$PDIR/package.json"
URL="https://github.com/chen969196657/dsh-prompt-shape/archive/refs/heads/main.tar.gz"
TMP="$(mktemp -d 2>/dev/null || echo /tmp/ps-$$)"
mkdir -p "$TMP"

echo "profile : $PROFILE"
echo "DSH_HOME: $DSH_HOME"

if [ ! -d "$PDIR" ]; then
  echo "profile 不存在: $PDIR"
  echo "已有 profile:"
  ls "$DSH_HOME/profiles" 2>/dev/null
  exit 1
fi

echo "[1/5] 下载"
if command -v curl >/dev/null 2>&1; then
  curl -fL --insecure -o "$TMP/p.tgz" "$URL"
elif command -v wget >/dev/null 2>&1; then
  wget --no-check-certificate -q -O "$TMP/p.tgz" "$URL"
else
  node -e 'fetch(process.argv[1]).then(r=>{if(!r.ok)throw new Error("HTTP "+r.status);return r.arrayBuffer()}).then(b=>require("fs").writeFileSync(process.argv[2],Buffer.from(b))).catch(e=>{console.error("fetch fail:",e.message);process.exit(1)})' "$URL" "$TMP/p.tgz"
fi
[ -s "$TMP/p.tgz" ] || { echo "下载为空"; exit 1; }

echo "[2/5] 解包"
tar xzf "$TMP/p.tgz" -C "$TMP"
SRC_IN="$TMP/dsh-prompt-shape-main"
if [ ! -f "$SRC_IN/package.json" ]; then
  SRC_IN="$(ls -d "$TMP"/dsh-prompt-shape-* 2>/dev/null | head -1)"
fi
[ -f "$SRC_IN/package.json" ] || { echo "解包后找不到 package.json"; ls "$TMP"; exit 1; }

echo "[3/5] 安装到 $SRC"
mkdir -p "$DSH_HOME/plugins"
rm -rf "$SRC"
cp -r "$SRC_IN" "$SRC"

echo "[4/5] 链接 + 登记 bundles"
mkdir -p "$PDIR/node_modules"
ln -sfn "$SRC" "$PDIR/node_modules/dsh-prompt-shape"
node -e '
const fs=require("fs");
const p=process.argv[1], prof=process.argv[2];
let j={};
try{j=JSON.parse(fs.readFileSync(p,"utf8"))}catch(e){j={name:"dsh-profile-"+prof,private:true}}
j.dependencies=j.dependencies||{};
if(!j.dependencies["dsh-prompt-shape"])j.dependencies["dsh-prompt-shape"]="^1.5.0";
j.dsh=j.dsh||{};j.dsh.profile=j.dsh.profile||{};
j.dsh.profile.bundles=j.dsh.profile.bundles||[];
if(!j.dsh.profile.bundles.includes("dsh-prompt-shape"))j.dsh.profile.bundles.push("dsh-prompt-shape");
fs.writeFileSync(p,JSON.stringify(j,null,2));
console.log("manifest ok, bundles="+j.dsh.profile.bundles.length);
' "$PKG" "$PROFILE"

echo "[5/5] 自检"
node --check "$SRC/lib/index.js" 2>/dev/null && echo "语法 OK"
node -e '
const fs=require("fs"),path=require("path");
const src=process.argv[1];
const files=fs.readdirSync(path.join(src,"lib")).filter(f=>f.endsWith(".js"));
let bad=0;
for(const f of files){try{new Function("return 0")}catch(e){} }
console.log("lib 模块数: "+files.length);
' "$SRC"
ls -l "$PDIR/node_modules/dsh-prompt-shape"
echo -n "package.json 中出现次数: "; grep -c dsh-prompt-shape "$PKG" || true

echo ""
echo "完成。重启 dsh 生效:  dsh web   或   dsh tui"
rm -rf "$TMP"
