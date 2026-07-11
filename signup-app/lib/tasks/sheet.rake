require "google/apis/sheets_v4"

# Builds the entire volunteer spreadsheet from scratch inside the sheet at
# SHEET_ID (create an empty Google Sheet, share it with the service account
# as Editor, then run this).
#
#   docker compose run --rm app bundle exec rake sheet:setup           # only if tabs absent
#   FORCE=1 docker compose run --rm app bundle exec rake sheet:setup   # wipe + rebuild tabs
#
# Customize via env: BOOTHS="A;B;C"  DAYS="Saturday;Sunday"  NEED=2
#                    OPEN="9:00 AM"  CLOSE="9:00 PM"  SLOT_MINUTES=120
#
# Tabs built: Signups (dropdown validations), Slot Needs (capacity grid),
# Volunteer Matrix (live formula view), Booth Chairs, Setup & Teardown.
# Any other tabs (e.g. "Schedule") are left untouched.
namespace :sheet do
  desc "Build/rebuild all volunteer tabs from scratch (FORCE=1 to overwrite)"
  task setup: :environment do
    booths = (ENV["BOOTHS"] || "Burgers, Brats, and Dogs;Chuck o Luck;Dime Toss;Pig Races;Information;Raffle;Duck Pond").split(";").map(&:strip)
    days = (ENV["DAYS"] || "Saturday;Sunday").split(";").map(&:strip)
    need = (ENV["NEED"] || "2").to_i
    slot_min = (ENV["SLOT_MINUTES"] || "120").to_i
    open_min = SheetService.to_minutes(ENV["OPEN"] || "9:00 AM")
    close_min = SheetService.to_minutes(ENV["CLOSE"] || "9:00 PM")
    abort "Bad OPEN/CLOSE time" unless open_min && close_min && close_min > open_min

    start_times = (open_min...close_min).step(slot_min).map { |m| SheetService.to_label(m) }
    end_times = ((open_min + slot_min)..close_min).step(slot_min).map { |m| SheetService.to_label(m) }

    svc = SheetService.new
    gs = svc.service
    sid = ENV.fetch("SHEET_ID")

    v = ->(rows) { Google::Apis::SheetsV4::ValueRange.new(values: rows) }
    write = ->(range, rows, input = "RAW") do
      gs.update_spreadsheet_value(sid, range, v.call(rows), value_input_option: input)
    end

    meta = gs.get_spreadsheet(sid)
    existing = meta.sheets.to_h { |s| [s.properties.title, s.properties.sheet_id] }

    tabs = {
      SheetService::SIGNUPS_TAB => nil,
      SheetService::NEEDS_TAB => nil,
      SheetService::MATRIX_TAB => nil,
      SheetService::CHAIRS_TAB => nil,
      SheetService::CREW_TAB => nil
    }

    clashes = tabs.keys & existing.keys
    if clashes.any? && !ENV["FORCE"]
      abort "Tabs already exist: #{clashes.join(', ')}. Re-run with FORCE=1 to wipe and rebuild them."
    end

    requests = []
    tabs.each_key do |title|
      next if existing.key?(title)
      requests << Google::Apis::SheetsV4::Request.new(
        add_sheet: Google::Apis::SheetsV4::AddSheetRequest.new(
          properties: Google::Apis::SheetsV4::SheetProperties.new(title: title)))
    end
    if requests.any?
      gs.batch_update_spreadsheet(sid, Google::Apis::SheetsV4::BatchUpdateSpreadsheetRequest.new(requests: requests))
      meta = gs.get_spreadsheet(sid)
      existing = meta.sheets.to_h { |s| [s.properties.title, s.properties.sheet_id] }
    end
    tabs.keys.each { |t| gs.clear_values(sid, "'#{t}'!A:Z") }

    # ---- Signups ----
    write.call("'#{SheetService::SIGNUPS_TAB}'!A1",
               [["First Name", "Last Name", "Email", "Phone", "Day", "Start Time", "End Time", "Booth"]])

    list_validation = ->(sheet_id, col, options) do
      Google::Apis::SheetsV4::Request.new(
        set_data_validation: Google::Apis::SheetsV4::SetDataValidationRequest.new(
          range: Google::Apis::SheetsV4::GridRange.new(
            sheet_id: sheet_id, start_row_index: 1, end_row_index: 1000,
            start_column_index: col, end_column_index: col + 1),
          rule: Google::Apis::SheetsV4::DataValidationRule.new(
            condition: Google::Apis::SheetsV4::BooleanCondition.new(
              type: "ONE_OF_LIST",
              values: options.map { |o| Google::Apis::SheetsV4::ConditionValue.new(user_entered_value: o) }),
            show_custom_ui: true, strict: false)))
    end
    signups_id = existing[SheetService::SIGNUPS_TAB]
    gs.batch_update_spreadsheet(sid, Google::Apis::SheetsV4::BatchUpdateSpreadsheetRequest.new(requests: [
      list_validation.call(signups_id, 4, days),
      list_validation.call(signups_id, 5, start_times),
      list_validation.call(signups_id, 6, end_times),
      list_validation.call(signups_id, 7, booths)
    ]))

    # ---- Slot Needs & Volunteer Matrix (same day-banner grid layout) ----
    col_letter = ->(idx) { ("B".ord + idx).chr } # booth columns start at B

    build_grid = ->(title_row, cell_for) do
      rows = [[title_row], ["Time"] + booths]
      days.each do |day|
        rows << ["", day]
        start_times.each do |t|
          rows << [t] + booths.each_index.map { |bi| cell_for.call(day, t, bi, rows.length + 1) }
        end
      end
      rows
    end

    needs_rows = build_grid.call("Volunteers needed per slot — organizers: edit these numbers",
                                 ->(_d, _t, _bi, _r) { need })
    write.call("'#{SheetService::NEEDS_TAB}'!A1", needs_rows)

    matrix_rows = build_grid.call("Who's working when — live view, do not edit (filled from Signups)",
                                  lambda do |day, _t, bi, row_num|
      col = col_letter.call(bi)
      "=IFERROR(TEXTJOIN(\", \", TRUE, FILTER(" \
        "'#{SheetService::SIGNUPS_TAB}'!$A$2:$A & \" \" & LEFT('#{SheetService::SIGNUPS_TAB}'!$B$2:$B, 1) & \".\", " \
        "'#{SheetService::SIGNUPS_TAB}'!$E$2:$E = \"#{day}\", " \
        "'#{SheetService::SIGNUPS_TAB}'!$H$2:$H = #{col}$2, " \
        "ARRAYFORMULA(IFERROR(TIMEVALUE('#{SheetService::SIGNUPS_TAB}'!$F$2:$F), 9)) <= TIMEVALUE($A#{row_num}), " \
        "ARRAYFORMULA(IFERROR(TIMEVALUE('#{SheetService::SIGNUPS_TAB}'!$G$2:$G), -9)) > TIMEVALUE($A#{row_num})" \
        ")), \"\")"
    end)
    write.call("'#{SheetService::MATRIX_TAB}'!A1", matrix_rows, "USER_ENTERED")

    # ---- Booth Chairs & Setup/Teardown ----
    write.call("'#{SheetService::CHAIRS_TAB}'!A1",
               [["First Name", "Last Name", "Email", "Phone", "Day", "Booth"]])
    write.call("'#{SheetService::CREW_TAB}'!A1",
               [["First Name", "Last Name", "Email", "Phone", "Crew"]])
    crew_id = existing[SheetService::CREW_TAB]
    gs.batch_update_spreadsheet(sid, Google::Apis::SheetsV4::BatchUpdateSpreadsheetRequest.new(requests: [
      list_validation.call(crew_id, 4, SheetService::CREWS)
    ]))

    puts "Built #{tabs.keys.join(', ')}"
    puts "#{booths.length} booths x #{days.length} days, #{slot_min}-min slots " \
         "#{start_times.first}–#{SheetService.to_label(close_min)}, #{need} volunteers per slot."
    puts "Organizers: adjust capacity in '#{SheetService::NEEDS_TAB}', watch '#{SheetService::MATRIX_TAB}' fill up."
  end
end
