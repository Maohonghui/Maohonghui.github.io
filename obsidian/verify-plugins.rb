# frozen_string_literal: true
#
# 本地验证脚本：直接跑两个插件的纯逻辑部分，不需要 Jekyll。
# 用法:  ruby obsidian/verify-plugins.rb

require "date"

$LOAD_PATH.unshift(File.expand_path("../_plugins", __dir__))

# 这两个插件末尾都会 register Jekyll::Hooks，本地没有 Jekyll，
# 所以先塞一个假的 Jekyll 模块进去。
module Jekyll
  class Hooks
    def self.register(*); end
  end

  module Logger
    def self.info(*); end

    def self.warn(*); end

    def self.debug(*); end
  end
end

require "post-frontmatter-normalizer"
require "sleep_log"

F = MaohonghuiBlog::FrontMatterNormalizer
S = MaohonghuiBlog::SleepLog

$failures = 0

def check(label, actual, expected)
  ok = actual == expected
  $failures += 1 unless ok
  puts format("  %-6s %-46s %s", ok ? "PASS" : "FAIL", label, actual.inspect)
  puts format("         %-46s expected %s", "", expected.inspect) unless ok
end

puts "=" * 78
puts "1) Front Matter 规范化（图片字段）"
puts "=" * 78

cases = [
  ["path:/ 前缀（Obsidian 最常见的坏值）", "path:/assets/img/posts/a.jpg", "/assets/img/posts/a.jpg"],
  ["path: 带空格", "path: /assets/My Image.jpg", "/assets/my%20image.jpg"],
  ["哈希对象的字符串形式（空）", '{"path"=>nil}', nil],
  ["空哈希字符串", "{}", nil],
  ["符号哈希字符串", '{:path=>"/a/b.jpg"}', "/a/b.jpg"],
  ["正常字符串路径", "/assets/img/posts/x.jpg", "/assets/img/posts/x.jpg"],
  ["相对路径 + 大写", "assets/img/Posts/UPPER.JPG", "/assets/img/posts/upper.jpg"],
  ["反斜杠", "assets\\img\\posts\\a.jpg", "/assets/img/posts/a.jpg"],
  ["外链必须原样保留", "https://github.com/Maohonghui.png", "https://github.com/Maohonghui.png"],
  ["http 外链", "http://example.com/a/b.png", "http://example.com/a/b.png"],
  ["中文文件名要转义", "/assets/img/我的封面.jpg", "/assets/img/%E6%88%91%E7%9A%84%E5%B0%81%E9%9D%A2.jpg"],
  ["开头的 ./ 去掉", "./assets/img/posts/a.jpg", "/assets/img/posts/a.jpg"],
  ["重复斜杠压缩", "//assets//img//a.jpg", "/assets/img/a.jpg"],
  ["查询串保留", "/assets/img/a.jpg?v=2#top", "/assets/img/a.jpg?v=2#top"],
  ["已转义的不要二次转义", "/assets/img/a%20b.jpg", "/assets/img/a%20b.jpg"],
  ["正常哈希", { "path" => "/assets/img/posts/ok.jpg" }, "/assets/img/posts/ok.jpg"],
  ["哈希 path 为 nil", { "path" => nil }, nil],
  ["空哈希", {}, nil],
  ["nil", nil, nil],
  ["空字符串", "", nil],
]

cases.each do |label, input, expected|
  check(label, F.normalize_path(F.extract_path(input)), expected)
end

puts
puts "  -- apply! 会剔除 pb-* 键并写回规范哈希 --"
data = { "image" => "path:/a/B.JPG", "pb-publish" => true, "pb-type" => "post", "title" => "t" }
F.apply!(data)
check("pb 键被剔除", data.keys.sort, %w[image title])
check("image 变成哈希", data["image"], { "path" => "/a/b.jpg" })
check("alt 缺省不写入", data["image"].key?("alt"), false)

data2 = { "image" => { "path" => "", "alt" => "封面" } }
F.apply!(data2)
check("空 path 时整个 image 被删除", data2.key?("image"), false)

data3 = { "image" => { "path" => "/a/b.jpg", "alt" => " 说明 ", "lqip" => "data:xx" } }
F.apply!(data3)
check("alt 去空白", data3["image"]["alt"], "说明")
check("lqip 保留", data3["image"]["lqip"], "data:xx")

puts
puts "=" * 78
puts "2) 早睡打卡解析"
puts "=" * 78

sample = <<~MD
  # 早睡打卡

  > 说明里出现 2026-01-01 不应该被算进去

  - [ ] 2026-10-08
  - [x] 2026-10-09
  - [X] 2026-10-10
  - [x] 2026-10-11 23:05 07:30
  - [x] 2026-10-12 22:40
  - [x] 2026-10-13 1:30 9:00
  - [x] 2026-10-15 23:00
  | [x] | 2026-10-16 | 备注 |
  - [x] 2026-10-17 23:59 06:00
  - [x] 2026-13-45
  - [x] 2026-02-30
  - [x] 2026-10-18
MD

entries = S.parse(sample)

check("未打勾的 10-08 被忽略", entries.key?("2026-10-08"), false)
check("说明文字里的日期被忽略", entries.key?("2026-01-01"), false)
check("非法月份 2026-13-45 被忽略", entries.key?("2026-13-45"), false)
check("非法日期 2026-02-30 被忽略", entries.key?("2026-02-30"), false)
check("只打勾无时间", entries["2026-10-09"], { "sleep_at" => nil, "wake_at" => nil })
check("大写 X 也算打勾", entries["2026-10-10"], { "sleep_at" => nil, "wake_at" => nil })
check("入睡+起床时间", entries["2026-10-11"], { "sleep_at" => "23:05", "wake_at" => "07:30" })
check("只有入睡时间", entries["2026-10-12"], { "sleep_at" => "22:40", "wake_at" => nil })
check("个位数时间补零", entries["2026-10-13"], { "sleep_at" => "01:30", "wake_at" => "09:00" })
check("表格写法", entries["2026-10-16"], { "sleep_at" => nil, "wake_at" => nil })
check("共解析出 9 条", entries.size, 9)

puts
puts "  -- 时间与阈值判定 --"
threshold = S.clock_to_minutes("23:00")
{
  "22:40" => true,
  "23:00" => true,
  "23:01" => false,
  "01:30" => false,
  "04:00" => false,
  "00:30" => false,
}.each do |clock, expected|
  check("#{clock} 算早睡? #{expected}", S.clock_to_minutes(clock) <= threshold, expected)
end

check("非法时间 24:00 归一化为 nil", S.normalize_clock("24:00"), nil)
check("非法时间 12:60 归一化为 nil", S.normalize_clock("12:60"), nil)
check("正常 09:05", S.normalize_clock("09:05"), "09:05")

puts
puts "=" * 78
puts "3) 用真实打卡笔记跑一遍 build 的核心逻辑"
puts "=" * 78

# 造 5 天数据，验证统计与 grid_offset
real = +"# 早睡打卡\n\n"
[["2026-10-05", "22:10"], ["2026-10-06", "23:30"], ["2026-10-07", "22:00"]].each do |d, t|
  real << "- [x] #{d} #{t}\n"
end
real << "- [ ] 2026-10-08\n"
real << "- [x] 2026-10-09\n"

parsed = S.parse(real)
check("解析出 4 条", parsed.size, 4)
check("10-05 入睡时间", parsed["2026-10-05"]["sleep_at"], "22:10")
check("10-09 只打勾", parsed["2026-10-09"], { "sleep_at" => nil, "wake_at" => nil })

# grid_offset：周一=0
[[Date.new(2026, 10, 5), 0], [Date.new(2026, 10, 8), 3], [Date.new(2026, 10, 11), 6]].each do |d, expected|
  actual = d.wday.zero? ? 6 : d.wday - 1
  check("#{d} 的 grid_offset = #{expected}", actual, expected)
  puts format("         (%s 是 %s)", d, %w[日 一 二 三 四 五 六][d.wday])
end

puts
puts "=" * 78
if $failures.zero?
  puts "全部通过 ✓"
else
  puts "#{$failures} 个失败 ✗"
end
puts "=" * 78

exit($failures.zero? ? 0 : 1)
