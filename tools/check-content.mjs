#!/usr/bin/env node
/**
 * check-content.mjs —— 发布前自检
 * ============================================================================
 *
 * 这个脚本回答一个问题：**我现在的文章，推上去会让 CI 挂掉吗？**
 *
 * 它检查的东西，正好是过去让构建失败的那几类问题：
 *
 *   1. Front Matter 里的 image.path 指向的文件在仓库里不存在
 *   2. 正文里 ![](/assets/...) 引用的图片不存在
 *   3. image.path 是空的 / 畸形的（就是以前产生 /{ 裂图的那种）
 *   4. 分类、标签、日期等必填字段缺失
 *   5. 文件名不符合 Jekyll 的 YYYY-MM-DD-xxx.md 规则
 *
 * 用法（在博客仓库根目录）：
 *   node tools/check-content.mjs
 *
 * 退出码 0 = 可以推；1 = 有问题，先修。
 */

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const POSTS_DIR = '_posts';
const problems = [];
const warnings = [];

/**
 * _posts/ 里允许存在的「非文章」文件。
 *
 * GitHub Publisher 只能把笔记发到 _posts/ 一个目录，所以打卡笔记这类
 * 纯数据文件也放在这里：它靠 `published: false` 不出现在博客上，
 * 由 _plugins/sleep_log.rb 读取。
 */
const NON_POST_FILES = new Set(['checkin.md']);

function readUtf8(p) {
  return fs.readFileSync(p, 'utf8');
}

/** 拆出 front matter 和正文 */
function splitFrontMatter(text) {
  const m = text.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?([\s\S]*)$/);
  if (!m) return { front: null, body: text };
  return { front: m[1], body: m[2] };
}

/** 极简 YAML 取值：够用即可，不引入依赖 */
function yamlValue(front, key) {
  const re = new RegExp(`^${key}:[ \\t]*(.*)$`, 'm');
  const m = front.match(re);
  if (!m) return undefined;
  return m[1].trim();
}

/** 取出 image 段落里的 path（支持缩进写法和一行写法） */
function extractImagePath(front) {
  const lines = front.split(/\r?\n/);
  const idx = lines.findIndex((l) => /^image:/.test(l));
  if (idx === -1) return { present: false, raw: null, path: null };

  const inline = lines[idx].replace(/^image:\s*/, '').trim();
  if (inline && inline !== '') {
    // 例：image: path:/xxx  或  image: /xxx
    const stripped = inline.replace(/^path\s*:\s*/, '').replace(/^["']|["']$/g, '');
    return { present: true, raw: inline, path: stripped };
  }

  // 缩进形式
  for (let i = idx + 1; i < lines.length; i++) {
    const line = lines[i];
    if (/^\S/.test(line)) break; // 回到顶层键，结束
    const m = line.match(/^\s+path\s*:\s*(.*)$/);
    if (m) {
      const v = m[1].trim().replace(/^["']|["']$/g, '');
      return { present: true, raw: line.trim(), path: v };
    }
  }
  return { present: true, raw: '(image: 但没有 path)', path: '' };
}

/** 收集正文里所有 markdown / html 图片引用 */
function collectBodyImages(body) {
  const out = [];
  for (const m of body.matchAll(/!\[[^\]]*\]\(([^)\s]+)/g)) out.push(m[1]);
  for (const m of body.matchAll(/<img[^>]+src=["']([^"']+)["']/g)) out.push(m[1]);
  return out;
}

function checkAssetExists(ref) {
  if (/^[a-z][a-z0-9+.-]*:\/\//i.test(ref) || ref.startsWith('data:')) return 'external';
  const clean = ref.split(/[?#]/)[0].replace(/^\//, '');
  const abs = path.join(process.cwd(), clean.split('/').join(path.sep));
  return fs.existsSync(abs) ? 'ok' : 'missing';
}

// ── 主流程 ──────────────────────────────────────────────────────────────────

if (!fs.existsSync('_config.yml')) {
  console.error('× 请在博客仓库根目录执行（找不到 _config.yml）');
  process.exit(1);
}

if (!fs.existsSync(POSTS_DIR)) {
  console.error(`× 找不到 ${POSTS_DIR} 目录`);
  process.exit(1);
}

const files = fs
  .readdirSync(POSTS_DIR)
  .filter((f) => !f.startsWith('.'))
  .sort();

if (files.length === 0) {
  console.log('_posts 里还没有文章。');
  process.exit(0);
}

console.log(`检查 ${files.length} 篇文章...\n`);

const FILENAME_RE = /^\d{4}-\d{2}-\d{2}-.+\.(md|markdown|html)$/;

/** 数据文件（不是文章）：只检查它是否安全地对博客隐藏 */
function checkNonPostFile(file) {
  const full = path.join(POSTS_DIR, file);
  const text = readUtf8(full);
  const { front } = splitFrontMatter(text);

  if (front === null) {
    problems.push(`${file}: 数据文件必须有 front matter（至少要有 published: false）`);
    return false;
  }

  const published = yamlValue(front, 'published');
  const hidden = yamlValue(front, 'hidden');

  if (published === 'false' || hidden === 'true') {
    console.log(`✓ ${file}  (数据文件，已对博客隐藏)`);
    return true;
  }

  problems.push(
    `${file}: 这是数据文件而不是文章，必须写 published: false，` +
      `否则它会作为一篇文章出现在首页上`
  );
  return false;
}

for (const file of files) {
  const full = path.join(POSTS_DIR, file);
  const notes = [];

  if (!fs.statSync(full).isFile()) {
    problems.push(`${file}: 不是普通文件（Jekyll 会忽略它，建议删掉）`);
    continue;
  }

  // 数据文件单独走一条检查路径
  if (NON_POST_FILES.has(file)) {
    checkNonPostFile(file);
    continue;
  }

  // 1. 文件名
  if (!FILENAME_RE.test(file)) {
    problems.push(`${file}: 文件名不符合 Jekyll 规则，应为 YYYY-MM-DD-标题.md`);
  }

  const text = readUtf8(full);
  const { front, body } = splitFrontMatter(text);

  if (front === null) {
    problems.push(`${file}: 缺少 Front Matter（文件开头要有 --- 包裹的 YAML）`);
    console.log(`✗ ${file}`);
    continue;
  }

  // 2. 必填字段
  const title = yamlValue(front, 'title');
  if (!title || title === '""' || title === "''") {
    problems.push(`${file}: title 是空的`);
  }

  const date = yamlValue(front, 'date');
  if (!date) {
    warnings.push(`${file}: 没有 date，Jekyll 会用文件名里的日期`);
  }

  const categories = front.match(/^categories:\s*$/m)
    ? front.split(/^categories:\s*$/m)[1].split(/^\S/m)[0]
    : '';
  if (/^\s*-\s*$/m.test(categories)) {
    warnings.push(`${file}: categories 下面是一个空的 "-"，建议删掉或填上分类`);
  }

  const tags = front.match(/^tags:\s*$/m)
    ? front.split(/^tags:\s*$/m)[1].split(/^\S/m)[0]
    : '';
  if (/^\s*-\s*$/m.test(tags)) {
    warnings.push(`${file}: tags 下面是一个空的 "-"，建议删掉或填上标签`);
  }

  // 3. 封面图
  const img = extractImagePath(front);
  let coverInfo = '无封面';
  if (img.present) {
    if (!img.path) {
      coverInfo = '无封面（path 为空）';
      // 空 path 不再是错误：插件会把它删掉，模板也做了防护
    } else if (img.path.startsWith('{')) {
      problems.push(`${file}: image.path 是畸形值 "${img.path}"，会产生 /{ 裂图`);
      coverInfo = '畸形';
    } else {
      const state = checkAssetExists(img.path);
      if (state === 'missing') {
        problems.push(`${file}: 封面图不存在 -> ${img.path}`);
        coverInfo = `缺失 ${img.path}`;
      } else if (state === 'external') {
        coverInfo = `外链 ${img.path}`;
      } else {
        coverInfo = `OK ${img.path}`;
      }
      if (img.path !== img.path.toLowerCase() && !/^[a-z][a-z0-9+.-]*:\/\//i.test(img.path)) {
        warnings.push(`${file}: image.path 含大写字母，Linux 上会 404 -> ${img.path}`);
      }
    }
  }

  // 3b. media_subpath 陷阱
  // Chirpy 的 media-url.html 会把 media_subpath 拼在图片路径前面。
  // 如果图片路径已经是以 / 开头的绝对路径，再设 media_subpath 就会路径翻倍：
  //   /assets/img/posts/assets/img/posts/xxx.jpg  -> 404
  const subpath = (yamlValue(front, 'media_subpath') || '').replace(/^["']|["']$/g, '');
  if (subpath) {
    const usesAbsolute = (img.path && img.path.startsWith('/')) ||
      collectBodyImages(body).some((r) => r.startsWith('/'));
    if (usesAbsolute) {
      problems.push(
        `${file}: media_subpath="${subpath}" 会让绝对图片路径翻倍 ` +
          `（主题会把它拼在前面），请改成 media_subpath: ""`
      );
    }
  }

  // 4. 正文图片
  const bodyImages = collectBodyImages(body);
  const missingBody = [];
  for (const ref of bodyImages) {
    const state = checkAssetExists(ref);
    if (state === 'missing') missingBody.push(ref);
    else if (state === 'ok' && ref !== ref.split(/[?#]/)[0].toLowerCase() && !/^[a-z][a-z0-9+.-]*:\/\//i.test(ref)) {
      warnings.push(`${file}: 正文图片路径含大写字母 -> ${ref}`);
    }
  }
  for (const ref of missingBody) {
    problems.push(`${file}: 正文图片不存在 -> ${ref}`);
  }

  const mark = problems.some((p) => p.startsWith(`${file}:`)) ? '✗' : '✓';
  console.log(`${mark} ${file}`);
  console.log(`    标题: ${title || '(空)'}`);
  console.log(`    封面: ${coverInfo}`);
  console.log(`    正文图: ${bodyImages.length} 张${missingBody.length ? `，缺 ${missingBody.length} 张` : ''}`);
}

// ── 汇总 ────────────────────────────────────────────────────────────────────

console.log('\n' + '─'.repeat(70));

if (warnings.length) {
  console.log(`\n提醒（${warnings.length} 条，不会让构建失败）：`);
  for (const w of warnings) console.log(`  ! ${w}`);
}

if (problems.length) {
  console.log(`\n错误（${problems.length} 条，会让构建或页面出问题）：`);
  for (const p of problems) console.log(`  × ${p}`);
  console.log('\n请先修掉这些问题再推送。');
  process.exit(1);
}

console.log('\n✓ 全部通过，可以放心推送。');
