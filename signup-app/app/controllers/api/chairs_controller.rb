require "uri"

module Api
  class ChairsController < ApplicationController
    def create
      # Honeypot: real users never fill the hidden "website" field. Pretend success.
      return render json: { ok: true }, status: :created if params[:website].present?

      first = params[:first_name].to_s.strip
      last  = params[:last_name].to_s.strip
      email = params[:email].to_s.strip
      phone = params[:phone].to_s.strip
      day   = params[:day].to_s.strip
      booth = params[:booth].to_s.strip

      if first.blank? || last.blank? || !email.match?(URI::MailTo::EMAIL_REGEXP)
        return render json: { error: "Please provide your first and last name and a valid email." },
                      status: :unprocessable_entity
      end
      if [first, last].any? { |v| v.length > 60 } || email.length > 120 || phone.length > 30
        return render json: { error: "That entry is too long." }, status: :unprocessable_entity
      end

      sheets = SheetService.new
      data = sheets.roster
      unless data[:days].include?(day) && data[:booths].include?(booth)
        return render json: { error: "That booth or day no longer exists — refresh the page and try again." },
                      status: :not_found
      end

      chairs = sheets.chair_rows
      if chairs.any? { |c| c[:day] == day && c[:booth] == booth }
        return render json: { error: "That booth just found its #{day} chair — pick another!" },
                      status: :conflict
      end
      if chairs.any? { |c| c[:day] == day && c[:email] == email.downcase }
        return render json: { error: "You're already chairing a booth on #{day}." }, status: :conflict
      end

      sheets.append_chair(first: first, last: last, email: email, phone: phone, day: day, booth: booth)
      Rails.cache.delete(Api::SlotsController::CACHE_KEY)

      render json: { ok: true, volunteer: sheets.public_name(first, last) }, status: :created
    rescue StandardError => e
      Rails.logger.error("chair signup error: #{e.class}: #{e.message}")
      render json: { error: "Something went wrong — please try again, or email the organizers." },
             status: :service_unavailable
    end
  end
end
