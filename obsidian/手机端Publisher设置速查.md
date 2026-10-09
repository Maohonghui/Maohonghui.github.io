# 手机端 GitHub Publisher 设置速查

> 这份笔记是为了让你在**手机上**照着一步步设。设完可以留着当备忘。

---

## 一、你截图里的设置 —— 全部正确 ✓

| 选项 | 你的值 | 判断 |
| --- | --- | --- |
| Branch | `main` | ✅ |
| **Content directory** | `_posts/` | ✅ 笔记会发布到仓库的 `_posts/` |
| **Assets directory** | `assets/` | ✅ 图片在仓库里实际存放的位置 |
| **Assets relative path** | `/assets/img/posts/` | ✅ 正文里图片链接写成什么 |
| **Use post type subdirectories** | 关（灰） | ✅ 关掉才对，否则会多一层子文件夹 |
| **Auto-publish** | 关（灰） | ✅ 关掉后只发 front matter 里有 `pb-publish: true` 的笔记 |

### ⚠️ 一个容易误改的地方

`Assets directory` = `assets/` 和 `Assets relative path` = `/assets/img/posts/`
**不一样是故意的、正确的**。它们分工不同：

- `Assets directory`：图片**上传到仓库的哪里** → `assets/`
- `Assets relative path`：正文里**链接写成什么** → `/assets/img/posts/xxx.jpg`

这两者配合出的结果正好对得上博客的目录结构（仓库里图片放在
`assets/img/posts/`，链接也写 `/assets/img/posts/xxx.jpg`）。
**不要把它们改成一样。**

---

## 二、Token（如果还没设或报过错）

必须是有 **Contents: Read and write** 权限的 fine-grained token：

1. 手机浏览器打开 https://github.com/settings/personal-access-tokens/new
2. **Token name**：`obsidian-blog`
3. **Expiration**：90 天（到期再换）
4. **Repository access** → `Only select repositories` → 勾 `Maohonghui.github.io`
5. **Permissions** → `Repository permissions` → 找到 **Contents** → 设为 **Read and write**
6. 生成，复制 `github_pat_...` 那串，粘到 Publisher 的 token 框

> 只开 Contents 这一项就够，其他都不用动。
> 只给 Read 的话推送会报 `Resource not accessible by personal access token`。

---

## 三、发文章

`博客/` 文件夹已经配好了 Templater 文件夹模板：

- 新建笔记放进 `博客/`
- 文件名会自动变成 `YYYY-MM-DD-HH-mm-ss`
- Front Matter 会自动填好（日期、封面、`pb-publish` 等）

你只需要填 `title` / `categories` / `tags`，然后：

> 命令面板 → `Upload single current active note`

等 1～2 分钟，网站自动更新。

---

## 四、发打卡（需要你确认一件事）

`checkin.md` 在**库的根目录**，它不能进 `_posts/`，
要发到**仓库根目录**（变成 `checkin.md`）。

你的 Publisher 现在只监视 `博客/` 一个文件夹，所以需要确认它有没有下面任一能力：

1. **按笔记单独指定目标位置**（某篇笔记可以发到仓库根目录）
2. **能加第二个监视文件夹**（除了 `博客/` 再加一个）

**有的话告诉我**，我把打卡接到你的发布动作上，你点一下方框 + 发一次就行。
**两者都没有也告诉我** —— 我换一个不用你额外操作的方案。

在你确认之前，打卡笔记暂时还不会自动更新到博客；博客上的「打卡」页会显示
"还没有读到打卡数据"。

---

## 五、自检清单

- [ ] Branch = `main`
- [ ] Content directory = `_posts/`
- [ ] Assets directory = `assets/`
- [ ] Assets relative path = `/assets/img/posts/`
- [ ] Use post type subdirectories = 关
- [ ] Token 有 Contents **读写**权限
- [ ] Templater 的文件夹模板已启用（我在电脑上帮你打开了）
- [ ] 新建笔记放进 `博客/` 会自动套模板并重命名

---

## 六、常见报错对照

| 报错 / 现象 | 原因 | 解决 |
| --- | --- | --- |
| `no pb set in frontmatter` | 笔记里缺 `pb-publish` | 用 `博客/` 的自动模板生成，别手写 Front Matter |
| `Resource not accessible by personal access token` | token 权限不够 | Contents 改成 Read and write |
| `Bad credentials` | token 复制不全或已过期 | 重新生成一个 |
| 图片 404 / 裂图 | 路径含大写，或缺了 `img/posts` | 全小写、以 `/assets/img/posts/` 开头 |
| 图片路径出现两遍 | 笔记里设了 `media_subpath` | 改成 `media_subpath: ""` |
| 推送成功但网页没变 | 构建中或构建失败 | 等 2 分钟；去仓库 Actions 页看日志 |
| 新建笔记没有自动命名 | Templater 文件夹模板没启用 | 在电脑上已帮你打开，手机同步后生效 |
