# 我的个人博客

Jekyll + [Chirpy](https://github.com/cotes2020/jekyll-theme-chirpy) 主题，部署在 GitHub Pages。
文章主要是在手机 Obsidian 里写的，通过 GitHub Publisher 推送过来。

**线上地址：** https://maohonghui.github.io

---

## 日常只用记两条命令

### 发布一篇文章

在手机 Obsidian 里写好、填好 Front Matter，然后：

> 命令面板 → `Upload single current active note`

推送后 GitHub Actions 会自动构建、校验、发布，约 1～2 分钟生效。

### 早睡打卡

在手机 Obsidian 里打开 `早睡打卡.md`，滑到底部点一下当天的方框，然后同样发布一次。

---

## 目录结构（只列需要关心的）

```
_posts/                      文章（Obsidian 发布到这里）
_tabs/                       左侧导航页：分类 / 标签 / 归档 / 早睡 / 关于
_layouts/                    覆盖主题的布局（加了图片安全渲染、去掉了授权声明）
_includes/                   覆盖主题的片段（footer 修好了 giscus 评论区）
_plugins/                    构建期插件，这是让站点「不容易坏」的关键
assets/img/posts/            所有文章配图
assets/img/favicons/         站点图标
tools/check-content.mjs      发布前自检
obsidian/使用说明.md          手机端完整操作说明 ★
obsidian/push-to-github.mjs  不开 git 也能推送的脚本
```

---

## 三个自定义插件（`_plugins/`）

### `post-frontmatter-normalizer.rb`

把 Obsidian 生成的畸形 Front Matter 修正掉。

Obsidian 的 GitHub Publisher 会把封面写成 `image: path:/xxx.jpg` 这种「看着像 YAML、
其实是字符串」的形式，或者写成 `image:` 下面跟一个空的 `path:`。
主题模板里有一句 `post.image.path | default: post.image`，遇到这两种情况就会把
**整个哈希对象**渲染进 `src`，产出这种垃圾：

```html
<img src="/{"path"=>nil}" alt="Preview Image">
```

浏览器会去请求 `/{`，于是首页裂图、htmlproofer 直接让构建失败。

这个插件在渲染前把 `image` 归一成规范的哈希；如果路径无效就删掉 `image` 键，
让模板走「无封面」分支。顺带还会：统一小写（Linux 区分大小写）、URL 编码中文和空格、
剔除 `pb-publish` / `pb-type` 这些发布插件专用的键。

### `sleep_log.rb`

把 Obsidian 的「早睡打卡」笔记变成热力图数据。

打卡笔记就是一串复选框：

```markdown
- [x] 2026-10-08 23:05 07:30
- [x] 2026-10-07
- [ ] 2026-10-06
```

Jekyll 自带的 `_data` 只认 yaml/json/csv/tsv，读不了 `.md`，所以用这个插件补上：
解析打卡、算出早睡率、当前连续、最长连续、以及每个格子该显示什么颜色。

判定规则：`23:00` 前入睡算早睡；只打勾不写时间也算早睡；没打勾算「没记录」（留空）。
跨午夜的时间会自动处理，`01:30` 会被当成「比 23:00 晚」。

阈值和统计天数在 `_config.yml` 里改：

```yaml
sleep_log:
  file: sleep-log.md
  days: 91
  threshold: "23:00"
```

### `posts-lastmod-hook.rb`

用 git 历史给文章补「更新于」时间。原版在 git 不可用时会抛异常把构建带崩，
这里改成了拿不到就安静跳过。

---

## 图片路径的两条铁律

这两条踩过坑，务必记住：

1. **路径必须以 `/` 开头，且全小写。**
   GitHub Pages 跑在 Linux 上，文件名区分大小写。手机上叫 `JPEG_abc.JPG`，
   Publisher 上传后会变成 `jpeg_abc.jpg`，文章里写大写就 404。

2. **绝对路径 + `media_subpath` = 路径翻倍。**
   主题的 `media-url.html` 会把 `media_subpath` 拼在图片路径前面。
   如果图片路径已经是 `/assets/img/posts/x.jpg`，再设
   `media_subpath: /assets/img/posts` 就会变成
   `/assets/img/posts/assets/img/posts/x.jpg`。
   **所以 `media_subpath` 必须留空。**

`tools/check-content.mjs` 会自动检查这两条。

---

## 发布前自检

改完文章后，推之前先跑一下：

```powershell
cd C:\Users\Tony\Desktop\myblog
node tools/check-content.mjs
```

它会检查：封面图/正文图是否存在、路径是否含大写、`media_subpath` 是否会导致翻倍、
文件名是否符合 Jekyll 规则、必填字段是否为空。退出码 0 才建议推送。

顺便也可以校验两个插件的逻辑（需要本地装 Ruby）：

```powershell
ruby obsidian/verify-plugins.rb
```

---

## 没有 git 也能推送

本机没装 git 时，用这个脚本走 GitHub API 建 commit：

```powershell
$env:GH_TOKEN = "你的 token"     # 需要 Contents: Read and write
node obsidian/push-to-github.mjs --branch main
```

它会逐个文件和远端比对，只提交真正变化的内容。

---

## 构建与校验

| 工作流 | 触发条件 | 作用 |
| --- | --- | --- |
| `pages-deploy.yml` | 推送到 `main` | 构建 → htmlproofer 校验 → 部署 |
| `build-test.yml` | 手动触发 / PR / `validate/**` 分支 | 只构建和校验，不部署 |

想在不影响线上的前提下验证改动，可以推到 `validate/xxx` 分支，
等 `Build Test` 绿了再合并到 main。

如果构建失败，去仓库 **Actions** 页面看日志。Front Matter 类的问题
日志里会指出具体是哪个文件。

---

## 已修复的历史问题（避免重复踩坑）

| 现象 | 原因 |
| --- | --- |
| 首页裂图、源码里出现 `/{` | `image:` 字段畸形，见上文插件说明 |
| 图片路径变成双份 | `media_subpath` 与绝对路径叠加 |
| `Ctrl+F5` 后正常、点链接又变旧 | PWA Service Worker 的 Cache-First 策略，已在 `_config.yml` 关闭 `pwa.cache`，并加了一次性注销脚本 |
| 评论区一直不显示 | `_includes/footer.html` 被清空，而 giscus 需要页面里有 `<footer>` 当插入锚点 |
| 页面浏览器标题为空 | `_tabs/*.md` 的 `title` 用了中文；主题要的是 ASCII 键名（中文由侧栏映射） |
| 文章底部有 CC BY 声明和分享按钮 | 已从 `_layouts/post.html` 移除，并清空 locale 里的 `copyright.license.template` |
| 侧栏出现空名字的导航项 | `_posts/` 下的 `.md`、`111` 这类垃圾文件，已删除 |

---

## 主题升级注意

`_layouts/home.html`、`_layouts/post.html`、`_includes/head.html` 是**整份覆盖**主题的。
升级 `jekyll-theme-chirpy` 之后，建议对比一下新版主题的同名文件，
把新增的功能合并进来，否则会停留在旧行为。

改动处都写了 `{%- comment -%}` 说明，搜索「覆盖」或看文件顶部注释即可定位。

---

## License

站点代码遵循仓库内 [MIT](LICENSE) 许可。
文章内容版权归作者所有。
