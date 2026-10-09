# frozen_string_literal: true
#
# 打卡插件的专项测试：多习惯解析 + 「次日 10:00 为界」的日期归属
# 用法: ruby obsidian/verify-checkin.rb

require "date"

$LOAD_PATH.unshift(File.expand_path("../_plugins", __dir__))

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

require "sleep_log"

C = MaohonghuiBlog::SleepLog
BOUNDARY = C.clock_to_minutes("10:00")

$failures = 0

def check(label, actual, expected)
  ok = actual == expected
  $failures += 1 unless ok
  puts format("  %-6s %-52s %s", ok ? "PASS" : "FAIL", label, actual.inspect)
  puts format("         %-52s expected %s", "", expected.inspect) unless ok
end

puts "=" * 80
puts "1) 「次日 10:00 为界」的日期归属（你的作息：当天 20:00 → 次日 10:00）"
puts "=" * 80

# date = 你写在那一行的日期；clock = 你填的入睡时间；结果 = 实际算作哪一晚
{
  ["2026-10-08", "23:30"] => "2026-10-08",  # 当晚 23:30，算 8 号
  ["2026-10-09", "01:10"] => "2026-10-08",  # 凌晨 1:10，仍算 8 号那晚
  ["2026-10-09", "09:59"] => "2026-10-08",  # 卡在边界前，算 8 号
  ["2026-10-09", "10:00"] => "2026-10-09",  # 正好 10:00，算 9 号
  ["2026-10-09", "20:30"] => "2026-10-09",  # 当晚 20:30，算 9 号
  ["2026-10-09", "00:00"] => "2026-10-08",  # 午夜整点，算 8 号
  ["2026-10-09", nil]      => "2026-10-09",  # 没填时间，就用你写的日期
  ["2026-01-01", "02:00"] => "2025-12-31",  # 跨年也要对
}.each do |(date, clock), expected|
  label = clock.nil? ? "#{date} 无时间" : "#{date} 入睡 #{clock}"
  check("#{label} → #{expected}", C.attribution_date(date, clock, BOUNDARY), expected)
end

puts
puts "=" * 80
puts "2) 多习惯解析"
puts "=" * 80

note = <<~MD
  # 习惯打卡

  > 这段说明里出现 2026-01-01 不应该被算进去

  ## 早睡
  - [x] 2026-10-08 23:30 07:30
  - [x] 2026-10-07 01:10
  - [ ] 2026-10-06
  - [x] 2026-10-05

  ## 锻炼
  - [x] 2026-10-08
  - [ ] 2026-10-07
  - [x] 2026-10-06

  ## 阅读
  - [x] 2026-10-08 22:00
MD

habits = C.parse(note, BOUNDARY)

check("解析出 3 个习惯", habits.keys.sort, %w[reading sleep workout])
check("说明文字里的日期被忽略", habits.values.any? { |h| h.key?("2026-01-01") }, false)
# 注意：10-07 那行写的 01:10 会被归到 10-06，所以 10-06 这一晚**有**记录；
# 但它是 01:10 得来的，不是 10-06 那行（那行是未打勾的）。
check("10-06 那一晚有记录（来自 10-07 的 01:10）", habits["sleep"].key?("2026-10-06"), true)
check("…入睡时间是 01:10", habits["sleep"]["2026-10-06"]["sleep_at"], "01:10")
check("早睡 10-08 入睡时间", habits["sleep"]["2026-10-08"]["sleep_at"], "23:30")
check("早睡 10-08 起床时间", habits["sleep"]["2026-10-08"]["wake_at"], "07:30")
check("10-07 本身没有记录（被归到 10-06）", habits["sleep"].key?("2026-10-07"), false)
check("只打勾不写时间", habits["sleep"]["2026-10-05"], { "sleep_at" => nil, "wake_at" => nil })
check("锻炼有 2 天", habits["workout"].size, 2)
check("锻炼 10-08 无时间", habits["workout"]["2026-10-08"], { "sleep_at" => nil, "wake_at" => nil })

puts
puts "=" * 80
puts "2b) 两行归到同一晚时的取舍"
puts "=" * 80

collide = <<~MD
  ## 早睡
  - [x] 2026-10-02 23:30
  - [x] 2026-10-03 01:00
MD
c = C.parse(collide, BOUNDARY)
check("10-02 与 10-03 01:00 合并成一晚", c["sleep"].keys, ["2026-10-02"])
check("取后出现的那条（01:00）", c["sleep"]["2026-10-02"]["sleep_at"], "01:00")

collide2 = <<~MD
  ## 早睡
  - [x] 2026-10-02 23:30
  - [x] 2026-10-03
MD
c2 = C.parse(collide2, BOUNDARY)
check("只有打勾没有时间时，不覆盖已有时间", c2["sleep"]["2026-10-02"]["sleep_at"], "23:30")

puts
puts "=" * 80
puts "3) 习惯名 → ASCII 键映射"
puts "=" * 80
{ "早睡" => "sleep", "锻炼" => "workout", "阅读" => "reading",
  "睡觉" => "sleep", "运动" => "workout", "冥想" => "meditation" }.each do |cn, slug|
  check("「#{cn}」→ #{slug}", C.habit_slug(cn), slug)
end

puts
puts "=" * 80
puts "4) 统计：连续天数 / 平均入睡时间"
puts "=" * 80

stats_note = <<~MD
  ## 早睡
  - [x] 2026-10-01 23:00
  - [x] 2026-10-02 23:30
  - [x] 2026-10-03 23:40
  - [x] 2026-10-04 22:30
  - [ ] 2026-10-05
  - [x] 2026-10-06 23:15
  - [x] 2026-10-07 23:45
MD

parsed = C.parse(stats_note, BOUNDARY)
first = Date.new(2026, 10, 1)
last = Date.new(2026, 10, 7)
habit = C.build_habit("sleep", parsed["sleep"], first, last, BOUNDARY)

check("7 天里没有归并（时间都在 10:00 之后）", parsed["sleep"].size, 6)
check("有记录天数", habit["stats"]["recorded_days"], 6)
check("最长连续（10-01~10-04 共 4 天）", habit["stats"]["streak_best"], 4)
check("当前连续（10-06、10-07 共 2 天）", habit["stats"]["streak_current"], 2)
check("格子总数 = 7 天", habit["days"].size, 7)
check("10-05 那天是空的", habit["days"][4]["done"], false)
check("10-01 那天有记录", habit["days"][0]["done"], true)
check("天数等于格子数", habit["stats"]["recorded_days"], habit["days"].count { |d| d["done"] })

# 平均入睡：23:00 23:30 23:40 22:30 23:15 23:45
# = 1380, 1410, 1420, 1350, 1395, 1425 → 合计 8380 / 6 = 1396.67 → 23:17
check("平均入睡时间", habit["stats"]["average_sleep"], "23:17")
check("最早入睡", habit["stats"]["earliest_sleep"], "22:30")
check("最晚入睡", habit["stats"]["latest_sleep"], "23:45")

# 凌晨入睡要按 +24h 计入平均，否则平均会被拉到中午附近
late_note = <<~MD
  ## 早睡
  - [x] 2026-10-01 23:00
  - [x] 2026-10-02 01:00
MD
late_parsed = C.parse(late_note, BOUNDARY)
late_habit = C.build_habit("sleep", late_parsed["sleep"], Date.new(2026, 10, 1), Date.new(2026, 10, 2), BOUNDARY)
check("两行归到同一晚，取后出现的 01:00", late_parsed["sleep"]["2026-10-01"]["sleep_at"], "01:00")
check("格子只有 10-01 有记录", late_parsed["sleep"].keys, ["2026-10-01"])
# 23:00 与 01:00 的平均是 00:00：如果不用 +24h 归一，会被算成中午 12:00
check("凌晨时间不把平均拉成中午", late_habit["stats"]["average_sleep"], "01:00")

puts
puts "=" * 80
puts "5) 干扰内容不能被当成打卡数据（回归测试）"
puts "=" * 80
puts "  背景：笔记顶部的说明里会写「例如 - [x] 2026-10-08 23:30 这样」"
puts "  早期版本没锚定行首，把说明里的示例也解析成了真实打卡。"

noisy = <<~MD
  # 习惯打卡

  > 例如 `- [x] 2026-10-08 23:30 07:30` 这样写。
  > 也可以写成 - [x] 2026-09-01 这种。

  <!-- 注释里的 - [x] 2026-09-02 也不该被算 -->

  正文提到 - [x] 2026-09-03 同样不行。

  ## 早睡
  - [x] 2026-10-01 23:30 07:30
  * [X] 2026-10-02 23:00
    - [x] 2026-10-03 01:10 09:00
  - [ ] 2026-10-04
  - [x] 2026-10-05
MD

noisy_habits = C.parse(noisy, BOUNDARY)

check("引用块/注释/正文里的示例都没被解析", noisy_habits["sleep"].keys.sort,
      ["2026-10-01", "2026-10-02", "2026-10-05"])
check("引用块里那个 2026-10-08 不存在", noisy_habits["sleep"].key?("2026-10-08"), false)
check("注释里那个 2026-09-02 不存在", noisy_habits["sleep"].key?("2026-09-02"), false)
check("正文里那个 2026-09-03 不存在", noisy_habits["sleep"].key?("2026-09-03"), false)
check("`*` 也是合法列表符", noisy_habits["sleep"].key?("2026-10-02"), true)
check("缩进的列表项也能解析（其 01:10 归到 10-02）",
      noisy_habits["sleep"]["2026-10-02"]["sleep_at"], "01:10")

puts
puts "=" * 80
puts $failures.zero? ? "全部通过 ✓" : "#{$failures} 个失败 ✗"
puts "=" * 80
exit($failures.zero? ? 0 : 1)
