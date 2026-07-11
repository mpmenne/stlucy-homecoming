require "google/apis/sheets_v4"
require "googleauth"

# Reads and writes the parish volunteer spreadsheet.
#
# Tabs (names overridable via *_TAB env vars):
#   "Slot Needs" (READ)  — grid: time rows x booth columns with a banner row
#       per day; each cell is the NUMBER of volunteers needed for that
#       2-hour slot. Organizers edit this to control capacity.
#   "Signups" (WRITE) — flat log the app appends to, one row per signup:
#       First Name | Last Name | Email | Phone | Day | Start Time | End Time | Booth
#   "Booth Chairs" (READ/WRITE) — one row per chaired booth-day:
#       First Name | Last Name | Email | Phone | Day | Booth
#   "Volunteer Matrix" — formula-driven human view for organizers; the app
#       never reads it. `rake sheet:setup` (re)builds everything.
class SheetService
  SCOPE = "https://www.googleapis.com/auth/spreadsheets".freeze
  NEEDS_TAB = ENV.fetch("NEEDS_TAB", "Slot Needs")
  SIGNUPS_TAB = ENV.fetch("SIGNUPS_TAB", "Signups")
  CHAIRS_TAB = ENV.fetch("CHAIRS_TAB", "Booth Chairs")
  CREW_TAB = ENV.fetch("CREW_TAB", "Setup & Teardown")
  MATRIX_TAB = ENV.fetch("MATRIX_TAB", "Volunteer Matrix")
  CREWS = ["Setup", "Teardown"].freeze
  DEFAULT_SLOT_MINUTES = 120
  DAY_NAME = /\A(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)\z/i

  def initialize
    @sheet_id = ENV.fetch("SHEET_ID")
  end

  # The full computed roster:
  # { days:, booths:, slot_minutes:,
  #   grid: { day => { booth => [{ time:, need:, names: ["Mike M.", ...] }] } } }
  def roster
    needs = parse_grid(values("#{NEEDS_TAB}!A1:Z300"))
    subs = signups

    grid = needs[:days].to_h do |day|
      [day, needs[:booths].to_h do |booth|
        [booth, needs[:grid][day][booth].map do |cell|
          t = self.class.to_minutes(cell[:time])
          covering = subs.select do |s|
            s[:day] == day && s[:booth] == booth &&
              s[:start_min] && s[:end_min] && s[:start_min] <= t && s[:end_min] > t
          end
          { time: cell[:time], need: cell[:value].to_i,
            names: covering.map { |s| public_name(s[:first], s[:last]) } }
        end]
      end]
    end

    { days: needs[:days], booths: needs[:booths],
      slot_minutes: infer_slot_minutes(needs), grid: grid }
  end

  def signups
    values("#{SIGNUPS_TAB}!A2:H").filter_map do |r|
      email = r[2].to_s.downcase.strip
      next if email.empty?
      {
        first: r[0].to_s.strip,
        last: r[1].to_s.strip,
        email: email,
        day: r[4].to_s.strip,
        start_min: self.class.to_minutes(r[5]),
        end_min: self.class.to_minutes(r[6]),
        booth: r[7].to_s.strip
      }
    end
  end

  def append_signup(first:, last:, email:, phone:, day:, start_label:, end_label:, booth:)
    row = [first, last, email, phone, day, start_label, end_label, booth]
    append("#{SIGNUPS_TAB}!A:H", row)
  end

  # Booth-chair assignments (full-day commitments). A booth-day with no row
  # still needs a chair. Missing tab => no assignments (logged) so shift
  # signups keep working regardless.
  def chair_rows
    values("#{CHAIRS_TAB}!A2:F").filter_map do |r|
      day = r[4].to_s.strip
      booth = r[5].to_s.strip
      next if day.empty? || booth.empty?
      {
        first: r[0].to_s.strip,
        last: r[1].to_s.strip,
        email: r[2].to_s.downcase.strip,
        day: day,
        booth: booth
      }
    end
  rescue StandardError => e
    Rails.logger.error("chair_rows error (is the '#{CHAIRS_TAB}' tab missing?): #{e.class}: #{e.message}")
    []
  end

  def append_chair(first:, last:, email:, phone:, day:, booth:)
    append("#{CHAIRS_TAB}!A:F", [first, last, email, phone, day, booth])
  end

  # Setup/teardown crew list: First Name | Last Name | Email | Phone | Crew.
  # Missing tab => empty lists (logged), same rationale as chair_rows.
  def crew_rows
    values("#{CREW_TAB}!A2:E").filter_map do |r|
      crew = r[4].to_s.strip.capitalize
      next unless CREWS.include?(crew)
      {
        first: r[0].to_s.strip,
        last: r[1].to_s.strip,
        email: r[2].to_s.downcase.strip,
        crew: crew
      }
    end
  rescue StandardError => e
    Rails.logger.error("crew_rows error (is the '#{CREW_TAB}' tab missing?): #{e.class}: #{e.message}")
    []
  end

  def append_crew(first:, last:, email:, phone:, crew:)
    append("#{CREW_TAB}!A:E", [first, last, email, phone, crew])
  end

  # "Mike" + "Menne" -> "Mike M." — how names appear publicly.
  def public_name(first, last)
    initial = last.to_s.strip.empty? ? "" : " #{last.strip[0].upcase}."
    "#{first.to_s.strip}#{initial}"
  end

  # "9:00 AM" -> 540. Returns nil for anything unparseable.
  def self.to_minutes(str)
    m = str.to_s.strip.match(/\A(\d{1,2}):(\d{2})\s*(AM|PM)\z/i)
    return nil unless m
    hour = m[1].to_i % 12
    hour += 12 if m[3].casecmp("PM").zero?
    hour * 60 + m[2].to_i
  end

  # 540 -> "9:00 AM"
  def self.to_label(minutes)
    h24 = (minutes / 60) % 24
    period = h24 >= 12 ? "PM" : "AM"
    hour = h24 % 12
    hour = 12 if hour.zero?
    format("%d:%02d %s", hour, minutes % 60, period)
  end

  def service
    @service ||= Google::Apis::SheetsV4::SheetsService.new.tap do |s|
      s.client_options.application_name = "stlucy-homecoming-signup"
      s.authorization = Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: File.open(ENV.fetch("GOOGLE_APPLICATION_CREDENTIALS")),
        scope: SCOPE
      )
    end
  end

  private

  # Generic day-banner grid parser. Finds the header row containing "Time",
  # then day banner rows (a lone weekday cell) and time rows.
  # => { days:, booths:, grid: { day => { booth => [{ time:, value: }] } } }
  def parse_grid(rows)
    time_col = nil
    booths = []
    days = []
    grid = {}
    current_day = nil

    rows.each do |row|
      cells = Array(row).map { |c| c.to_s.strip }

      if time_col.nil?
        idx = cells.index("Time")
        if idx
          time_col = idx
          booths = cells[(idx + 1)..].reject(&:empty?)
        end
        next
      end

      non_empty = cells.reject(&:empty?)
      next if non_empty.empty?

      if non_empty.length == 1 && non_empty.first.match?(DAY_NAME)
        current_day = non_empty.first.capitalize
        days << current_day
        grid[current_day] = booths.to_h { |b| [b, []] }
        next
      end

      time = cells[time_col].to_s
      next if current_day.nil? || self.class.to_minutes(time).nil?

      booths.each_with_index do |booth, i|
        grid[current_day][booth] << { time: time, value: cells[time_col + 1 + i].to_s }
      end
    end

    { days: days, booths: booths, grid: grid }
  end

  def infer_slot_minutes(needs)
    day = needs[:days].first
    booth = needs[:booths].first
    rows = day && booth ? needs[:grid][day][booth] : []
    return DEFAULT_SLOT_MINUTES if rows.length < 2

    a = self.class.to_minutes(rows[0][:time])
    b = self.class.to_minutes(rows[1][:time])
    a && b && b > a ? b - a : DEFAULT_SLOT_MINUTES
  end

  def values(range)
    service.get_spreadsheet_values(@sheet_id, range).values || []
  end

  def append(range, row)
    service.append_spreadsheet_value(
      @sheet_id,
      range,
      Google::Apis::SheetsV4::ValueRange.new(values: [row]),
      value_input_option: "USER_ENTERED"
    )
  end
end
