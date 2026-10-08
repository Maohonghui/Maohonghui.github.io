# frozen_string_literal: true
#
# sleep_log.rb
#
# 从「早睡打卡」笔记里读出打卡数据，变成网站可以直接用的 site.data['sleep']。
#
# 为什么要有这个插件
# ------------------
# 打卡笔记是 Obsidian 里的一篇 Markdown，用 GitHub Publisher 直接发布到博客仓库，
# 内容长这样：
#
#     # 早睡打卡
#
#     - [x] 2026-10-08 23:05 07:30
#     - [x] 2026-10-07
#     - [ ] 2026-10-06
#
# Jekyll 自带的 _data 只认 yaml/yml/json/csv/tsv，读不了 .md。
# 这个插件就是补上这一段：把 [] / [x] 解析成日期列表，
# 再算出热力图需要的所有数据（连续天数、早睡率、每个格子的状态）。
#
# 好处是：你在手机上只需要点一下复选框，不需要任何转换、脚本或额外操作。
#
# 文件放在仓库根目录的 sleep-log.md（可以用 _config.yml 里的 sleep_log.file 改）。

require "date"
require "pathname"

module MaohonghuiBlog
  module SleepLog
    # - [x] 2026-10-08 23:05 07:30
    # - [X] 2026-10-08
    # | [x] | 2026-10-08 | ... |   （兼容表格写法）
    # 故意写得很宽松：复选框和日期之间可以是空格、竖线、多个空格
    CHECKBOX_RE = /\[([ xX✓✔])\][\s|]*(\d{4}-\d{2}-\d{2})([^\n]*)/

    # 从行尾里挑出时间。先贪心地匹配任何 H:MM，交给 normalize_clock 过滤，
    # 这样 24:00 这种非法时间不会把后面的有效时间挤到错误的位置（比如把起床时间
    # 当成入睡时间）。
    TIME_RE = /(\d{1,2}:\d{2})/

    DEFAULT_FILE = "sleep-log.md"
    DEFAULT_DAYS = 91
    DEFAULT_THRESHOLD = "23:00"

    module_function

    # 把 "23:05" 变成分钟数；凌晨时间算作跨过 0 点，方便和阈值比较
    def clock_to_minutes(clock)
      return nil if clock.nil?

      hour, minute = clock.split(":").map(&:to_i)
      return nil unless hour && minute

      total = hour * 60 + minute
      total += 24 * 60 if total < 12 * 60
      total
    end

    def normalize_clock(raw)
      return nil if raw.nil?

      match = raw.to_s.strip.match(/\A(\d{1,2}):(\d{2})\z/)
      return nil unless match

      hour = match[1].to_i
      minute = match[2].to_i
      return nil unless hour.between?(0, 23) && minute.between?(0, 59)

      format("%02d:%02d", hour, minute)
    end

    # 解析整篇笔记，返回 { "2026-10-08" => { sleep_at:, wake_at: } }
    def parse(content)
      entries = {}

      content.each_line do |line|
        match = line.match(CHECKBOX_RE)
        next if match.nil?

        checked = match[1].downcase == "x" || ["✓", "✔"].include?(match[1])
        next unless checked

        date = match[2]

        # 校验日期真实存在，挡掉 2026-13-45 这种
        begin
          Date.parse(date)
        rescue ArgumentError, TypeError
          next
        end

        times = match[3].to_s.scan(TIME_RE).flatten.map { |t| normalize_clock(t) }.compact

        entries[date] = {
          "sleep_at" => times[0],
          "wake_at" => times[1]
        }
      end

      entries
    end

    def build(site)
      config = site.config["sleep_log"] || {}
      rel_path = config["file"] || DEFAULT_FILE
      days_window = (config["days"] || DEFAULT_DAYS).to_i
      threshold = normalize_clock(config["threshold"]) || DEFAULT_THRESHOLD

      unless rel_path.to_s.empty?
        absolute = Pathname.new(rel_path.to_s).absolute? ? rel_path.to_s : File.join(site.source, rel_path)
      end
      unless absolute && File.file?(absolute)
        Jekyll.logger.info "SleepLog:", "跳过（找不到 #{rel_path}）"
        return nil
      end

      content = File.read(absolute, encoding: "UTF-8")
      entries = parse(content)

      today = Date.today
      # 统计区间：默认取最近 N 天；如果打卡记录比今天更新，就以最晚的那天为准
      last_date = today
      parsed_dates = entries.keys.map { |d| Date.parse(d) rescue nil }.compact
      last_date = parsed_dates.max if parsed_dates.max && parsed_dates.max > today

      first_date = last_date - (days_window - 1)

      threshold_minutes = clock_to_minutes(threshold)

      days = []
      cursor = first_date
      while cursor <= last_date
        key = cursor.iso8601
        entry = entries[key]

        early = nil
        sleep_at = nil
        wake_at = nil

        if entry
          sleep_at = entry["sleep_at"]
          wake_at = entry["wake_at"]
          # 有具体入睡时间就按时间判断；只有勾选没写时间，就算作早睡
          early = if sleep_at
                    minutes = clock_to_minutes(sleep_at)
                    minutes.nil? ? true : minutes <= threshold_minutes
                  else
                    true
                  end
        end

        days << {
          "date" => key,
          "early" => early,
          "sleep_at" => sleep_at,
          "wake_at" => wake_at
        }
        cursor += 1
      end

      recorded = days.count { |d| !d["early"].nil? }
      early_days = days.count { |d| d["early"] == true }

      # 当前连续：从最后一天往前数
      streak_current = 0
      days.reverse_each do |d|
        break unless d["early"] == true

        streak_current += 1
      end

      # 最长连续
      streak_best = 0
      running = 0
      days.each do |d|
        if d["early"] == true
          running += 1
          streak_best = running if running > streak_best
        else
          running = 0
        end
      end

      rate = recorded.zero? ? 0.0 : (early_days.to_f / recorded * 100).round(1)

      {
        "generated_at" => Time.now.strftime("%Y-%m-%d"),
        "window" => {
          "start" => first_date.iso8601,
          "end" => last_date.iso8601,
          "days" => days.length,
          # 热力图周一在第 0 行，所以第一列前面要空出几天
          "grid_offset" => first_date.wday.zero? ? 6 : first_date.wday - 1
        },
        "early_threshold" => threshold,
        "stats" => {
          "recorded_days" => recorded,
          "early_days" => early_days,
          "early_rate" => rate,
          "streak_current" => streak_current,
          "streak_best" => streak_best
        },
        "days" => days
      }
    end
  end
end

# pre_render 比主题生成数据更早，保证 Liquid 里一定能拿到 site.data['sleep']
Jekyll::Hooks.register :site, :pre_render do |site|
  data = MaohonghuiBlog::SleepLog.build(site)
  site.data["sleep"] = data unless data.nil?
rescue StandardError => e
  Jekyll.logger.warn "SleepLog:", "解析失败，热力图将显示为空：#{e.message}"
end
