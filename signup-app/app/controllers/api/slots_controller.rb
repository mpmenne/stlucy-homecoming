module Api
  class SlotsController < ApplicationController
    CACHE_KEY = "roster-payload".freeze

    def index
      payload = Rails.cache.fetch(CACHE_KEY, expires_in: 30.seconds) do
        svc = SheetService.new
        data = svc.roster
        assigned = svc.chair_rows.to_h { |c| [[c[:day], c[:booth]], svc.public_name(c[:first], c[:last])] }
        crew_list = svc.crew_rows
        {
          days: data[:days],
          booths: data[:booths],
          slotMinutes: data[:slot_minutes],
          grid: data[:days].to_h do |day|
            [day, data[:booths].to_h do |booth|
              [booth, data[:grid][day][booth].map do |cell|
                cell.merge(open: [cell[:need] - cell[:names].length, 0].max)
              end]
            end]
          end,
          chairs: data[:days].flat_map do |day|
            data[:booths].map { |booth| { day: day, booth: booth, chair: assigned[[day, booth]] || "" } }
          end,
          crew: SheetService::CREWS.to_h do |crew|
            [crew, crew_list.select { |c| c[:crew] == crew }
                            .map { |c| svc.public_name(c[:first], c[:last]) }]
          end
        }
      end
      render json: payload
    rescue StandardError => e
      Rails.logger.error("slots error: #{e.class}: #{e.message}")
      render json: { error: "Unable to load the schedule right now." }, status: :service_unavailable
    end
  end
end
