---
layout: page
# 见 categories.md 的说明：title 要用 ASCII 键名，中文在 _data/locales/zh-CN.yml 的 tabs.sleep
title: sleep
icon: fas fa-moon
order: 5
---

> 这里记录我每天几点睡。目标很简单：**23:00 之前上床**。
{: .prompt-tip }

{% include sleep-heatmap.html lang=lang %}

## 怎么看这张图

- **浅灰**：那天没有打卡记录（不是"没早睡"，只是没记）
- **深色**：有记录，但没在 23:00 前睡
- **绿色**：23:00 前睡着了

鼠标停在格子上（手机上是长按）可以看到那天的具体入睡/起床时间。

## 数据是怎么来的

数据不在博客里手写，而是从 Obsidian 的 daily notes 自动生成：

1. 在手机 Obsidian 的 daily note 里勾上 `早睡早起`
   （实际就是那行 `- [早睡早起::]` 变成 `- [早睡早起::true]`）
2. 在电脑上跑一次生成脚本
3. 推送，博客自动重新构建

```powershell
cd C:\Users\Tony\Desktop\myblog
python obsidian/generate_sleep_data.py

$env:GH_TOKEN = "你的token"
node obsidian/push-to-github.mjs --branch main
```

想调整统计口径，比如改成 22:30，加一个参数即可：

```powershell
python obsidian/generate_sleep_data.py --threshold "22:30" --days 180
```
