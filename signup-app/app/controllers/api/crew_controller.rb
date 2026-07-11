require "uri"

module Api
  class CrewController < ApplicationController
    def create
      # Honeypot: real users never fill the hidden "website" field. Pretend success.
      return render json: { ok: true }, status: :created if params[:website].present?

      first = params[:first_name].to_s.strip
      last  = params[:last_name].to_s.strip
      email = params[:email].to_s.strip
      phone = params[:phone].to_s.strip
      crew  = params[:crew].to_s.strip.capitalize

      unless SheetService::CREWS.include?(crew)
        return render json: { error: "Unknown crew — refresh the page and try again." },
                      status: :unprocessable_entity
      end
      if first.blank? || last.blank? || !email.match?(URI::MailTo::EMAIL_REGEXP)
        return render json: { error: "Please provide your first and last name and a valid email." },
                      status: :unprocessable_entity
      end
      if [first, last].any? { |v| v.length > 60 } || email.length > 120 || phone.length > 30
        return render json: { error: "That entry is too long." }, status: :unprocessable_entity
      end

      sheets = SheetService.new
      if sheets.crew_rows.any? { |c| c[:crew] == crew && c[:email] == email.downcase }
        return render json: { error: "You're already on the #{crew.downcase} crew — thank you!" },
                      status: :conflict
      end

      sheets.append_crew(first: first, last: last, email: email, phone: phone, crew: crew)
      Rails.cache.delete(Api::SlotsController::CACHE_KEY)

      render json: { ok: true, volunteer: sheets.public_name(first, last) }, status: :created
    rescue StandardError => e
      Rails.logger.error("crew signup error: #{e.class}: #{e.message}")
      render json: { error: "Something went wrong — please try again, or email the organizers." },
             status: :service_unavailable
    end
  end
end
