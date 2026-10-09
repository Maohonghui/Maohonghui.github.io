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

  # 有些插件会通过 Jekyll.logger 输出诊断信息，这里一起 stub 掉
  class NullLogger
    def info(*); end

    def warn(*); end

    def debug(*); end

    def error(*); end
  end

  def self.logger
    @logger ||= NullLogger.new
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

  # ── 回归：老的博客文章模板会让人把 Obsidian 嵌入语法整串贴进 path ──
  # 没剥掉 ![[ ]] 的话会被当成普通文本做 URL 编码，
  # 生成 /%21%5B%5Bassets/... 这种坏链接，封面直接裂。
  #
  # 注意这里只测「路径规范化」这一层（不传 site）。
  # 真正把路径修正到磁盘上真实文件的是下面的 resolve_asset_path，
  # 那一层单独测。
  ["嵌入语法 ![[文件名]]", "![[cover.jpg]]", "/cover.jpg"],
  ["嵌入语法 + path: 前缀（双重错误）", "path:![[assets/cover.jpg]]", "/cover.jpg"],
  ["嵌入语法剥掉 assets/ 前缀", "![[assets/img/posts/cover.jpg]]", "/img/posts/cover.jpg"],
  ["嵌入语法带中文", "![[我的封面.jpg]]", "/%E6%88%91%E7%9A%84%E5%B0%81%E9%9D%A2.jpg"],
  ["内部链接 [[文件名]]", "[[cover.jpg]]", "/cover.jpg"],
  # 不带括号的正常相对路径要保持原样，不能去掉 assets/
  ["裸的 assets/ 前缀保持不变", "assets/cover.jpg", "/assets/cover.jpg"],
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
puts "2) Front Matter 中图片路径不匹配时的自动纠正"
puts "=" * 78

# 这是为了让「手机上怎么写都不裂图」成立的关键一层。
# Obsidian 的 Front Matter 是手写的，很容易漏掉 img/posts 这一段。
require "tmpdir"
require "fileutils"

Dir.mktmpdir do |dir|
  FileUtils.mkdir_p(File.join(dir, "assets", "img", "posts"))
  FileUtils.mkdir_p(File.join(dir, "assets"))
  File.write(File.join(dir, "assets", "img", "posts", "cover.jpg"), "x")
  File.write(File.join(dir, "assets", "legacy.jpg"), "x")

  fake_site = Struct.new(:source).new(dir)
  # 清掉缓存，保证用新的临时目录
  F.instance_variable_set(:@asset_index, nil)
  F.instance_variable_set(:@asset_index_src, nil)

  check("路径完全正确时原样返回",
        F.resolve_asset_path("/assets/img/posts/cover.jpg", fake_site),
        "/assets/img/posts/cover.jpg")

  check("少了 img/posts 时按文件名纠正",
        F.resolve_asset_path("/assets/cover.jpg", fake_site),
        "/assets/img/posts/cover.jpg")

  check("只写文件名时按文件名纠正",
        F.resolve_asset_path("/cover.jpg", fake_site),
        "/assets/img/posts/cover.jpg")

  check("直接在 assets 根目录的图片也能找到",
        F.resolve_asset_path("/assets/legacy.jpg", fake_site),
        "/assets/legacy.jpg")

  check("找不到的图片保持原样（交给 htmlproofer 报错）",
        F.resolve_asset_path("/assets/nope.jpg", fake_site),
        "/assets/nope.jpg")
end

puts
puts "=" * 78
puts "3) 早睡打卡的解析逻辑"
puts "=" * 78
puts "  → 已拆到独立文件 obsidian/verify-checkin.rb"
puts "    （那边的用例更全：多习惯、次日 10:00 为界的日期归属、统计口径）"
puts "    运行： ruby obsidian/verify-checkin.rb"

puts
puts "=" * 78
if $failures.zero?
  puts "全部通过 ✓"
else
  puts "#{$failures} 个失败 ✗"
end
puts "=" * 78

exit($failures.zero? ? 0 : 1)
