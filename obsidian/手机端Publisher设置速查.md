# 手机端 GitHub Publisher 设置速查

> 这份笔记是为了让你在**手机上**照着一步步设。设完就可以删掉，或者留着当备忘。

---

## 一、先确认版本

打开 Obsidian → 设置 → 第三方插件，找到你的发布插件，看名字：

| 插件名 | 说明 |
| --- | --- |
| **GitHub Publisher** | 旧版，用 `pb-publish` 这类键 |
| **Enveloppe** | 新版（改名后的同一作者版本），设置项更全 |

两个的配置思路基本一样，下面的选项名我会同时给出常见的两种写法。
**如果某个选项你找不到，把设置页截图发我，我按你的版本给你准确路径。**

---

## 二、必须设置的项（按重要性排序）

### 1. GitHub 账号与仓库（`GitHub` 分组）

| 选项（可能的名字） | 填什么 |
| --- | --- |
| Username / GitHub username | `Maohonghui` |
| Repository name / Repo | `Maohonghui.github.io` |
| Branch | `main` |
| GitHub token / Token | 见下面第三节 |

填完点一下 **`Test the connection`**（或 `Check connection`），必须显示成功再往下走。

### 2. Token（`GitHub` 分组）

**这是最容易出问题的一项。** 你的 token 必须是 **fine-grained** 且带 **Contents: Read and write**。

生成步骤：

1. 手机浏览器打开 https://github.com/settings/personal-access-tokens/new
2. **Token name**：`obsidian-blog`
3. **Expiration**：90 天（到期再换）
4. **Repository access** → `Only select repositories` → 勾 `Maohonghui.github.io`
5. **Permissions** → `Repository permissions` → 找到 **Contents** → 设为 **Read and write**
6. 生成，复制 `github_pat_...` 开头那串，粘到 Publisher 的 token 框

> ⚠️ 只开 Contents 这一项就够了，其他权限都不用动。
> 如果只给 Read，推送会报 `Resource not accessible by personal access token`。

### 3. 文件路径（`File` / `Upload` 分组）

| 选项（可能的名字） | 填什么 |
| --- | --- |
| File path / Default folder / Folder | `_posts` |
| Use post type subdirectories | **关闭 / Off** |
| Filename / 文件名格式 | 保持默认（用笔记标题） |

`Use post type subdirectories` 一定要关，否则会多生成一层子文件夹。

### 4. 图片与附件（`File` / `Attachment` 分组）

| 选项（可能的名字） | 填什么 |
| --- | --- |
| Image folder / Attachment folder / Default image folder | `assets/img/posts` |
| Copy attachments / Upload images | 开启 |

### 5. Front Matter 里的发布开关（`Front matter` 分组）

这是插件判断"这篇要不要发"的依据。你的笔记里已经有这两行：

```yaml
pb-publish: true
pb-type: post
```

在设置里找到类似 **`Key to publish`** / **`Publish key`** 的选项，确认它对应的是
`pb-publish`（旧版）或 `share`（新版 Enveloppe 的默认）。

> **如果对不上**：把设置里那个键名改成和笔记一致，或者告诉我，我把模板里的键名改成你插件认的那个。

---

## 三、设置完的自检清单

按顺序过一遍，每项都要打勾：

- [ ] `Test the connection` 成功
- [ ] Username 是 `Maohonghui`
- [ ] Repository 是 `Maohonghui.github.io`
- [ ] Branch 是 `main`
- [ ] Token 有 Contents **读写**权限
- [ ] File path = `_posts`
- [ ] `Use post type subdirectories` = Off
- [ ] Image folder = `assets/img/posts`
- [ ] 发布开关的 key 是 `pb-publish`（或你插件认的那个）

---

## 四、试发一篇

1. 新建笔记，文件名起成 `2026-10-09-测试发布`
2. 命令面板 → `Templater: Insert template` → 选「博客文章模板」
3. 填 `title`、`categories`、`tags`
4. 命令面板 → `Upload single current active note`
5. 等 1～2 分钟，打开 https://maohonghui.github.io 看有没有出现

**成功的样子**：GitHub 仓库的 `_posts/` 下多了 `2026-10-09-测试发布.md`，
Actions 页面出现一条绿色的 `Build and Deploy`。

---

## 五、打卡笔记的额外设置

`checkin.md` 和文章不一样，它要发到**仓库根目录**，不能发到 `_posts`。

它就在库的根目录（不在 `博客/` 里），所以：

- 打开 `checkin.md`
- 在 Publisher 里把这篇的目标位置设成**仓库根目录**，文件名保持 `checkin`
- 发布

> **如果你的 Publisher 只能设一个全局文件夹**（比如所有笔记都只能进 `_posts`），
> 那这篇发不过去。先告诉我，我给你换方案。

## 六、常见报错对照

| 报错 | 原因 | 解决 |
| --- | --- | --- |
| `no pb set in frontmatter` | 笔记里缺 `pb-publish` | 用模板生成，别手写 Front Matter |
| `Resource not accessible by personal access token` | token 权限不够 | Contents 改成 Read and write |
| `Bad credentials` | token 复制不全或已过期 | 重新生成一个 |
| 图片 404 / 裂图 | 路径含大写字母 | 全部改成小写；Linux 区分大小写 |
| 图片路径出现两遍 | 笔记里设了 `media_subpath` | 把它改成 `media_subpath: ""` |
| 推送成功但网页没变 | 构建还在跑，或构建失败 | 等 2 分钟；去仓库 Actions 页看日志 |
