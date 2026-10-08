/**
 * push-to-github.mjs
 *
 * 不依赖本地 git：直接用 GitHub REST API 建一个 commit 并推送到指定分支。
 * 会把工作区和远端 HEAD 的文件逐一比对，只提交真正有变化的文件。
 *
 * 用法（在博客仓库根目录执行）:
 *   $env:GH_TOKEN = "你的token"
 *   node obsidian/push-to-github.mjs --branch main
 *   node obsidian/push-to-github.mjs --branch validate/fixes --message "临时验证"
 */

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { createHash } from 'node:crypto';

const OWNER = 'Maohonghui';
const REPO = 'Maohonghui.github.io';
const API = `https://api.github.com/repos/${OWNER}/${REPO}`;

const TOKEN = process.env.GH_TOKEN;
if (!TOKEN) {
  console.error('缺少环境变量 GH_TOKEN');
  process.exit(1);
}

const HEADERS = {
  'User-Agent': 'dsh-blog-publisher',
  Accept: 'application/vnd.github+json',
  Authorization: `Bearer ${TOKEN}`,
};

async function api(url, options = {}, tries = 4) {
  for (let attempt = 1; attempt <= tries; attempt++) {
    try {
      const res = await fetch(url, {
        ...options,
        headers: { ...HEADERS, ...(options.headers || {}) },
      });
      if (res.status === 403 || res.status === 429 || res.status >= 500) {
        if (attempt === tries) {
          throw new Error(`${options.method || 'GET'} ${url} -> ${res.status} ${await res.text()}`);
        }
        await new Promise((r) => setTimeout(r, 1500 * attempt));
        continue;
      }
      if (!res.ok) {
        throw new Error(`${options.method || 'GET'} ${url} -> ${res.status} ${await res.text()}`);
      }
      return res.status === 204 ? null : res.json();
    } catch (err) {
      if (attempt === tries) throw err;
      await new Promise((r) => setTimeout(r, 1500 * attempt));
    }
  }
}

function parseArgs(argv) {
  let branch = null;
  let message = null;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--branch' || argv[i] === '-b') branch = argv[++i];
    else if (argv[i] === '--message' || argv[i] === '-m') message = argv[++i];
  }
  return { branch, message };
}

// ── 本地扫描 ────────────────────────────────────────────────────────────────
const IGNORE_DIRS = new Set([
  '.git', '.jekyll-cache', '_site', 'node_modules', '_theme_ref', '.bundle', 'vendor', '.vscode-test',
  // 本地排查用的产物目录，绝对不该提交
  '_site_check', '_site_probe', 'tmp', '.tmp',
]);
const IGNORE_FILES = new Set(['.DS_Store', 'Thumbs.db', 'Gemfile.lock', 'package-lock.json']);

function walk(dir, root, acc = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (IGNORE_DIRS.has(entry.name) || IGNORE_FILES.has(entry.name)) continue;
    const full = path.join(dir, entry.name);
    const rel = path.relative(root, full).split(path.sep).join('/');
    if (entry.isDirectory()) {
      // 空目录 git 不跟踪，直接跳过
      if (fs.readdirSync(full).length === 0) continue;
      walk(full, root, acc);
    } else if (entry.isFile()) {
      acc.push(rel);
    }
  }
  return acc;
}

const BINARY_RE = /\.(png|jpe?g|gif|webp|avif|ico|woff2?|ttf|otf|eot|pdf|zip|gz|gem|exe|dll)$/i;

function readBytes(abs, rel) {
  const raw = fs.readFileSync(abs);
  if (BINARY_RE.test(rel)) return raw;
  // 文本文件统一成 LF，避免把 Windows 的 CRLF 提交进仓库
  const text = raw.toString('utf8').replace(/\r\n/g, '\n');
  return Buffer.from(text, 'utf8');
}

function gitBlobSha(buffer) {
  return createHash('sha1')
    .update(Buffer.concat([Buffer.from(`blob ${buffer.length}\0`, 'utf8'), buffer]))
    .digest('hex');
}

// ── 主流程 ──────────────────────────────────────────────────────────────────
async function main() {
  const { branch, message } = parseArgs(process.argv.slice(2));
  if (!branch) {
    console.error('用法: node obsidian/push-to-github.mjs --branch <branch> [--message "..."]');
    process.exit(1);
  }

  const root = process.cwd();
  if (!fs.existsSync(path.join(root, '_config.yml'))) {
    console.error('× 请在博客仓库根目录执行（找不到 _config.yml）');
    process.exit(1);
  }

  // 1. 决定父提交 / 基线
  let parentSha;
  let baseTreeSha;
  try {
    const ref = await api(`${API}/git/ref/heads/${branch}`);
    parentSha = ref.object.sha;
    console.log(`分支 ${branch} 已存在，父提交 ${parentSha.slice(0, 8)}`);
  } catch {
    const mainRef = await api(`${API}/git/ref/heads/main`);
    parentSha = mainRef.object.sha;
    console.log(`分支 ${branch} 不存在，从 main (${parentSha.slice(0, 8)}) 派生`);
  }
  const parentCommit = await api(`${API}/git/commits/${parentSha}`);
  baseTreeSha = parentCommit.tree.sha;

  // 2. 远端快照
  const remoteTree = await api(`${API}/git/trees/${baseTreeSha}?recursive=1`);
  if (remoteTree.truncated) console.warn('! 远端 tree 被截断，比对可能不完整');

  const remoteBlobs = new Map();
  const remoteGitlinks = new Map();
  for (const node of remoteTree.tree) {
    if (node.type === 'blob') remoteBlobs.set(node.path, node.sha);
    else if (node.type === 'commit') remoteGitlinks.set(node.path, node.sha);
  }

  // 3. 本地快照
  const localFiles = walk(root, root);
  const localSet = new Set(localFiles);

  // 4. 逐个文件比对，只上传有变化的
  const entries = [];
  const changed = [];

  for (const rel of localFiles) {
    const abs = path.join(root, rel.split('/').join(path.sep));
    const buffer = readBytes(abs, rel);

    if (remoteBlobs.get(rel) === gitBlobSha(buffer)) continue;

    const blob = await api(`${API}/git/blobs`, {
      method: 'POST',
      body: JSON.stringify({ content: buffer.toString('base64'), encoding: 'base64' }),
    });

    entries.push({ path: rel, mode: '100644', type: 'blob', sha: blob.sha });
    changed.push(rel);
  }

  // 5. 远端存在、本地没有 -> 删除
  const removed = [];
  const KEEP_GITLINK = new Set(['.gitmodules']);

  for (const remotePath of remoteBlobs.keys()) {
    if (KEEP_GITLINK.has(remotePath)) continue; // .gitmodules 保留，submodule 原样不动
    if (!localSet.has(remotePath)) {
      entries.push({ path: remotePath, mode: '100644', type: 'blob', sha: null });
      removed.push(remotePath);
    }
  }

  if (entries.length === 0) {
    console.log('\n没有需要提交的改动，分支已是最新。');
    return;
  }

  console.log(`\n有变化的文件 (${changed.length}):`);
  for (const f of changed) console.log(`  M ${f}`);
  if (removed.length) {
    console.log(`\n删除的文件 (${removed.length}):`);
    for (const f of removed) console.log(`  D ${f}`);
  }

  // 6. tree -> commit -> 更新分支
  const newTree = await api(`${API}/git/trees`, {
    method: 'POST',
    body: JSON.stringify({ base_tree: baseTreeSha, tree: entries }),
  });

  const commitMessage =
    message ||
    [
      'fix: 修复图片渲染与缓存问题，重做 Obsidian 写作流程',
      '',
      '- _plugins: 新增 Front Matter 规范化插件，兜住 Obsidian 生成的畸形 image 字段',
      '- _layouts/_includes: 封面图安全渲染，不再产生 /{ 这类非法路径',
      '- _includes/footer.html: 恢复 footer，修复 giscus 评论区不显示的问题',
      '- _config.yml: 关闭 PWA Service Worker 缓存，头像改成本地资源',
      '- 文章底部: 移除 CC BY 授权声明与分享按钮',
      '- 资源整理: 图片归入 assets/img/posts，补齐 favicon 全套',
      '- CI: 恢复 htmlproofer 校验，新增 Build Test 工作流',
    ].join('\n');

  const commit = await api(`${API}/git/commits`, {
    method: 'POST',
    body: JSON.stringify({ message: commitMessage, tree: newTree.sha, parents: [parentSha] }),
  });

  try {
    await api(`${API}/git/refs/heads/${branch}`, {
      method: 'PATCH',
      body: JSON.stringify({ sha: commit.sha, force: false }),
    });
  } catch {
    await api(`${API}/git/refs`, {
      method: 'POST',
      body: JSON.stringify({ ref: `refs/heads/${branch}`, sha: commit.sha }),
    });
  }

  console.log(`\n✓ 已推送到 ${branch}`);
  console.log(`  commit: ${commit.sha}`);
  console.log(`  https://github.com/${OWNER}/${REPO}/commit/${commit.sha}`);
}

main().catch((err) => {
  console.error('× 失败:', err.message);
  process.exit(1);
});
