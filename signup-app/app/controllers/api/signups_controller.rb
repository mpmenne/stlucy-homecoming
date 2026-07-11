require "uri"

module Api
  class SignupsController < ApplicationController
    def create
      # Honeypot: real users never fill the hidden "website" field. Pretend success.
      return render json: { ok: true }, status: :created if params[:website].present?

      first = params[:first_name].to_s.strip
      last  = params[:last_name].to_s.strip
      email = params[:email].to_s.strip
      phone = params[:phone].to_s.strip
      day   = params[:day].to_s.strip
      booth = params[:booth].to_s.strip
      start_label = params[:start].to_s.strip
      end_label   = params[:end].to_s.strip

      if first.blank? || last.blank? || !email.match?(URI::MailTo::EMAIL_REGEXP)
        return render json: { error: "Please provide your first and last name and a valid email." },
                      status: :unprocessable_entity
      end
      if [first, last].any? { |v| v.length > 60 } || email.length > 120 || phone.length > 30
        return render json: { error: "That entry is too long." }, status: :unprocessable_entity
      end

      start_min = SheetService.to_minutes(start_label)
      end_min = SheetService.to_minutes(end_label)
      if start_min.nil? || end_min.nil? || end_min <= start_min
        return render json: { error: "Please pick a valid start and end time." },
                      status: :unprocessable_entity
      end

      sheets = SheetService.new
      # Fresh read (not the 30s cache) so capacity checks are current.
      data = sheets.roster
      rows = data.dig(:grid, day, booth)
      unless rows
        return render json: { error: "That booth or day no longer exists — refresh the page and try again." },
                      status: :not_found
      end

      slot_min = data[:slot_minutes]
      if ((end_min - start_min) % slot_min) != 0
        return render json: { error: "Please pick a valid start and end time." },
                      status: :unprocessable_entity
      end

      # The range must land exactly on grid slots: start on a slot boundary and
      # every covered slot present in the day's schedule.
      expected_times = (start_min...end_min).step(slot_min).to_a
      grid_times = rows.map { |r| SheetService.to_minutes(r[:time]) }
      unless (expected_times - grid_times).empty?
        return render json: { error: "Please pick times within the #{day} schedule." },
                      status: :unprocessable_entity
      end
      covered = rows.select { |r| expected_times.include?(SheetService.to_minutes(r[:time])) }
      if covered.any? { |r| r[:names].length >= r[:need] }
        return render json: { error: "Part of that time range just filled up — pick another time." },
                      status: :conflict
      end

      overlapping_dup = sheets.signups.any? do |s|
        s[:email] == email.downcase && s[:day] == day && s[:booth] == booth &&
          s[:start_min] && s[:end_min] && s[:start_min] < end_min && s[:end_min] > start_min
      end
      if overlapping_dup
        return render json: { error: "You're already signed up for that booth during that time." },
                      status: :conflict
      end

      sheets.append_signup(first: first, last: last, email: email, phone: phone,
                           day: day, start_label: start_label, end_label: end_label, booth: booth)
      Rails.cache.delete(Api::SlotsController::CACHE_KEY)

      render json: { ok: true, volunteer: sheets.public_name(first, last) }, status: :created
    rescue StandardError => e
      Rails.logger.error("signup error: #{e.class}: #{e.message}")
      render json: { error: "Something went wrong — please try again, or email the organizers." },
             status: :service_unavailable
    end
  end
end
