#!/usr/bin/env node
/**
 * upload-image.mjs —— 把图片放进博客的 assets/img/posts/，并给出可复制的 Markdown 片段
 * ============================================================================
 *
 * 为什么需要它
 * ------------
 * GitHub Publisher 在手机上把图片推到 GitHub 时，会把文件名转成小写。
 * 而 GitHub Pages 跑在 Linux 上，文件名区分大小写：
 * 本地写 ![](/assets/img/posts/JPEG_abc.JPG)、仓库里其实是 jpeg_abc.jpg，
 * 结果就是图片 404、显示裂图。
 *
 * 这个脚本做三件事：
 *   1. 把文件名统一成「小写 + 只含 ASCII 安全字符 + 带时间戳」（避免重名覆盖）
 *   2. 复制到 assets/img/posts/
 *   3. 打印可以直接粘贴到 Obsidian 里的 Markdown / Front Matter 片段
 *
 * 用法（在博客仓库根目录执行）：
 *   node tools/upload-image.mjs "C:\\Users\\Tony\\Desktop\\cover.jpg"
 *   node tools/upload-image.mjs ./照片.jpg --name my-cover
 *
 * 也可以一次传多张：
 *   node tools/upload-image.mjs a.jpg b.jpg c.jpg
 */

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const TARGET_DIR = path.join('assets', 'img', 'posts');

const IMAGE_EXT = new Set(['.jpg', '.jpeg', '.png', '.gif', '.webp', '.avif', '.svg', '.bmp']);

/** 依据文件头判断真实格式，比扩展名可靠 */
function sniffExtension(buffer) {
  if (buffer.length < 12) return null;
  const hex = buffer.subarray(0, 12).toString('hex');

  if (hex.startsWith('ffd8ff')) return '.jpg';
  if (hex.startsWith('89504e470d0a1a0a')) return '.png';
  if (hex.startsWith('47494638')) return '.gif';
  if (hex.startsWith('52494646') && buffer.subarray(8, 12).toString('ascii') === 'WEBP') return '.webp';
  if (buffer.subarray(4, 12).toString('ascii').startsWith('ftypavif')) return '.avif';
  if (hex.startsWith('424d')) return '.bmp';
  if (hex.startsWith('3c737667') || hex.startsWith('3c3f786d')) return '.svg';
  return null;
}

/** 把任意名字变成安全的 URL slug */
function slugify(name) {
  return name
    .normalize('NFKD')
    .replace(/[^\x00-\x7F]/g, '')       // 丢掉非 ASCII（中文等）
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 48);
}

function stamp(date = new Date()) {
  const p = (n) => String(n).padStart(2, '0');
  return (
    `${date.getFullYear()}${p(date.getMonth() + 1)}${p(date.getDate())}` +
    `_${p(date.getHours())}${p(date.getMinutes())}${p(date.getSeconds())}`
  );
}

function human(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(2)} MB`;
}

function parseArgs(argv) {
  const inputs = [];
  let name = null;
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--name' || arg === '-n') {
      name = argv[++i];
    } else if (arg === '--help' || arg === '-h') {
      console.log(fs.readFileSync(new URL(import.meta.url), 'utf8').split('*/')[0]);
      process.exit(0);
    } else {
      inputs.push(arg);
    }
  }
  return { inputs, name };
}

function main() {
  const { inputs, name } = parseArgs(process.argv.slice(2));

  if (inputs.length === 0) {
    console.error('用法: node tools/upload-image.mjs <图片路径> [更多图片...] [--name 自定义名字]');
    console.error('例:   node tools/upload-image.mjs "C:\\Users\\Tony\\Desktop\\cover.jpg"');
    process.exit(1);
  }

  if (!fs.existsSync('_config.yml')) {
    console.error('× 当前目录看起来不是博客仓库根目录（找不到 _config.yml）');
    console.error('  请先 cd 到仓库根目录再执行。');
    process.exit(1);
  }

  fs.mkdirSync(TARGET_DIR, { recursive: true });

  const results = [];

  for (const input of inputs) {
    const abs = path.resolve(input);

    if (!fs.existsSync(abs)) {
      console.error(`× 找不到文件: ${input}`);
      continue;
    }

    const buffer = fs.readFileSync(abs);
    const declared = path.extname(abs).toLowerCase();
    const actual = sniffExtension(buffer);

    if (!actual && !IMAGE_EXT.has(declared)) {
      console.error(`× 不像图片文件，跳过: ${input}`);
      continue;
    }

    if (actual && declared && actual !== declared) {
      console.log(`! ${path.basename(input)} 的扩展名是 ${declared}，实际格式是 ${actual}，按实际格式处理`);
    }

    const ext = actual || declared;
    const base = name ? slugify(name) : slugify(path.basename(abs, path.extname(abs)));
    const stem = base ? `${base}_${stamp()}` : `img_${stamp()}`;
    const filename = `${stem}${ext}`;
    const dest = path.join(TARGET_DIR, filename);

    fs.copyFileSync(abs, dest);
    const destSize = fs.statSync(dest).size;

    results.push({ filename, size: destSize, url: `/assets/img/posts/${filename}` });

    console.log(`✓ ${path.basename(input)}  →  ${dest}   (${human(destSize)})`);
    if (destSize > 2 * 1024 * 1024) {
      console.log(`  ! 这张图有 ${human(destSize)}，建议先压缩（tinypng.com），否则手机流量打开会很慢`);
    }
  }

  if (results.length === 0) return;

  console.log('\n' + '─'.repeat(72));
  console.log('把下面内容粘到 Obsidian 笔记里：\n');

  if (results.length === 1) {
    const r = results[0];
    console.log('【正文里插入图片】');
    console.log(`![](${r.url})\n`);
    console.log('【当作封面】把 Front Matter 的 image 改成：');
    console.log('image:');
    console.log(`  path: ${r.url}`);
    console.log('  alt: ""');
  } else {
    console.log('【正文里插入图片】');
    for (const r of results) console.log(`![](${r.url})`);
  }

  console.log('\n' + '─'.repeat(72));
  console.log('提示：这些路径已经保证是全小写的，不会再出现 Linux 大小写导致的 404。');
}

main();
