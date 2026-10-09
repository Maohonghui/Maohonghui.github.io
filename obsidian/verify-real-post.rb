# frozen_string_literal: true
#
# 用「模板真实生成的文章」喂给构建插件，确认不会出问题。
# 用法: ruby obsidian/verify-real-post.rb "_posts/xxx.md"  （不给参数则检查 _posts 下全部）
#
# 这个脚本存在的意义：模板里改一个字符，都可能让生成的文章在构建时炸掉。
# 与其等 CI 报错，不如本地先跑一遍。

require "date"
require "yaml"

$LOAD_PATH.unshift(File.expand_path("../_plugins", __dir__))

module Jekyll
  class Hooks
    def self.register(*); end
  end

  class NullLogger
    def info(*args)
      puts "  [info] #{args.join(' ')}"
    end

    def warn(*args)
      puts "  [WARN] #{args.join(' ')}"
    end

    def debug(*); end
  end

  def self.logger
    @logger ||= NullLogger.new
  end
end

require "post-frontmatter-normalizer"

F = MaohonghuiBlog::FrontMatterNormalizer
$failures = 0

def check(label, actual, expected)
  ok = actual == expected
  $failures += 1 unless ok
  puts format("  %-6s %-48s %s", ok ? "PASS" : "FAIL", label, actual.inspect)
  puts format("         %-48s expected %s", "", expected.inspect) unless ok
end

def split_front_matter(text)
  m = text.match(/\A---\r?\n(.*?)\r?\n---\r?\n?(.*)\z/m)
  return [nil, text] if m.nil?

  [m[1], m[2]]
end

files = if ARGV.empty?
          Dir.glob(File.join(__dir__, "..", "_posts", "*.md")).sort
        else
          ARGV
        end

if files.empty?
  puts "没有找到要检查的文章。"
  exit 1
end

puts "=" * 80
puts "检查模板生成的真实文章（共 #{files.size} 篇）"
puts "=" * 80

files.each do |path|
  name = File.basename(path)
  puts "\n── #{name} ──"

  unless File.file?(path)
    check("文件存在", false, true)
    next
  end

  text = File.read(path, encoding: "UTF-8")
  front, body = split_front_matter(text)

  if front.nil?
    check("有 front matter", false, true)
    next
  end
  check("有 front matter", true, true)

  # 1. YAML 能不能解析？解析出什么类型？
  data = begin
    YAML.safe_load(front, permitted_classes: [Time, Date, DateTime])
  rescue Psych::SyntaxError => e
    puts "  [FAIL] YAML 语法错误: #{e.message}"
    $failures += 1
    nil
  end

  if data.is_a?(Hash)
    check("front matter 解析成哈希", true, true)
  elsif data.nil?
    check("front matter 解析成哈希", false, true)
    next
  else
    check("front matter 解析成哈希（实际是 #{data.class}）", false, true)
    next
  end

  # 2. 关键字段
  title = data["title"]
  check("title 非空", !title.to_s.strip.empty?, true)
  check("title 不含模板语法残留 (<% )", title.to_s.include?("<%"), false)
  check("date 存在", !data["date"].nil?, true)
  check("categories 是数组", data["categories"].is_a?(Array), true)
  check("tags 是数组", data["tags"].is_a?(Array), true)

  # 3. image 经插件规范化后必须是安全形状
  F.apply!(data, nil)
  if data.key?("image")
    img = data["image"]
    check("image 是哈希", img.is_a?(Hash), true)
    check("image.path 是字符串", img["path"].is_a?(String), true) if img.is_a?(Hash)
    check("image.path 不以 { 开头", img.is_a?(Hash) && img["path"].to_s.start_with?("{"), false)
  else
    puts "  [info] 无封面（image 已被移除，走无封面分支）—— 这是安全的"
  end

  # 4. 不应残留发布插件专用键
  check("pb-publish 被剔除", data.key?("pb-publish"), false)
  check("pb-type 被剔除", data.key?("pb-type"), false)

  # 5. media_subpath 必须为空或不存在（否则图片路径翻倍）
  sub = data["media_subpath"].to_s
  check("media_subpath 为空", sub.empty?, true)

  # 6. 正文开头不应残留模板注释
  check("正文没有残留模板说明", body.lstrip.start_with?("<!--"), true)
end

puts
puts "=" * 80
puts $failures.zero? ? "全部通过 ✓" : "#{$failures} 个失败 ✗"
puts "=" * 80
exit($failures.zero? ? 0 : 1)
