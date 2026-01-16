# frozen_string_literal: true

require "kiket_sdk"
require "json"
require "net/http"
require "uri"
require "logger"

# Google Calendar Extension for Kiket
# Syncs Google Calendar events to team capacity planning
class GoogleCalendarExtension
  class GoogleAPIError < StandardError
    attr_reader :status_code

    def initialize(message, status_code: nil)
      super(message)
      @status_code = status_code
    end
  end

  GOOGLE_CALENDAR_API_BASE = "https://www.googleapis.com/calendar/v3"

  EVENT_TYPE_MAPPING = {
    "holiday" => %w[holiday bank\ holiday],
    "pto" => %w[vacation pto out\ of\ office ooo],
    "travel" => %w[travel flight trip],
    "focus" => %w[focus deep\ work heads\ down],
    "training" => %w[training learning workshop]
  }.freeze

  def initialize
    @sdk = KiketSDK.new(manifest_path: ".kiket/manifest.yaml")
    @logger = Logger.new($stdout)

    register_kiket_handlers
    register_api_routes
  end

  def app
    @sdk
  end

  def run!(host: "0.0.0.0", port: 9292)
    @sdk.run!(host: host, port: port)
  end

  private

  # =============================================================================
  # Kiket Webhook Handlers
  # =============================================================================

  def register_kiket_handlers
    @sdk.register("calendar.sync", version: "1.0",
                  required_scopes: %w[calendars.read capacity.write]) do |payload, context|
      handle_calendar_sync(payload, context)
    end

    @sdk.register("calendar.list", version: "1.0",
                  required_scopes: %w[calendars.read]) do |payload, context|
      handle_list_calendars(payload, context)
    end

    @sdk.register("calendar.events", version: "1.0",
                  required_scopes: %w[calendars.read]) do |payload, context|
      handle_get_events(payload, context)
    end

    @sdk.register("googleCalendar.syncNow", version: "1.0",
                  required_scopes: %w[calendars.read capacity.write]) do |payload, context|
      handle_calendar_sync(payload, context)
    end

    @sdk.register("googleCalendar.listCalendars", version: "1.0",
                  required_scopes: %w[calendars.read]) do |payload, context|
      handle_list_calendars(payload, context)
    end
  end

  def handle_calendar_sync(payload, context)
    access_token = context&.dig(:oauth, :access_token) || payload["access_token"]
    return { ok: false, error: "No access token available" } unless access_token

    user_id = payload["user_id"]
    calendar_ids = payload["calendar_ids"] || ["primary"]
    sync_window_days = payload["sync_window_days"] || 180

    time_min = Time.now.utc.iso8601
    time_max = (Time.now.utc + (sync_window_days * 24 * 60 * 60)).iso8601

    all_events = []
    errors = []

    calendar_ids.each do |calendar_id|
      begin
        events = fetch_events(access_token, calendar_id, time_min, time_max)
        processed_events = events.map { |event| process_event(event, calendar_id) }
        all_events.concat(processed_events)
      rescue GoogleAPIError => e
        errors << { calendar_id: calendar_id, error: e.message }
      end
    end

    {
      ok: true,
      user_id: user_id,
      events_synced: all_events.count,
      calendars_synced: calendar_ids.count - errors.count,
      events: all_events,
      errors: errors.presence
    }
  rescue StandardError => e
    { ok: false, error: e.message }
  end

  def handle_list_calendars(payload, context)
    access_token = context&.dig(:oauth, :access_token) || payload["access_token"]
    return { ok: false, error: "No access token available" } unless access_token

    calendars = fetch_calendars(access_token)

    {
      ok: true,
      calendars: calendars.map do |cal|
        {
          id: cal["id"],
          name: cal["summary"],
          description: cal["description"],
          timezone: cal["timeZone"],
          access_role: cal["accessRole"],
          primary: cal["primary"] || false
        }
      end
    }
  rescue GoogleAPIError => e
    { ok: false, error: e.message }
  end

  def handle_get_events(payload, context)
    access_token = context&.dig(:oauth, :access_token) || payload["access_token"]
    return { ok: false, error: "No access token available" } unless access_token

    calendar_id = payload["calendar_id"] || "primary"
    time_min = payload["time_min"] || Time.now.utc.iso8601
    time_max = payload["time_max"] || (Time.now.utc + (30 * 24 * 60 * 60)).iso8601

    events = fetch_events(access_token, calendar_id, time_min, time_max)

    {
      ok: true,
      calendar_id: calendar_id,
      events: events.map { |event| process_event(event, calendar_id) }
    }
  rescue GoogleAPIError => e
    { ok: false, error: e.message }
  end

  # =============================================================================
  # REST API Routes
  # =============================================================================

  def register_api_routes
    register_health_route
    register_calendars_route
    register_events_route
    register_sync_route
  end

  def register_health_route
    @sdk.app.get "/health" do
      content_type :json
      {
        status: "healthy",
        service: "google-calendar",
        version: "1.0.0",
        timestamp: Time.now.utc.iso8601
      }.to_json
    end
  end

  def register_calendars_route
    extension = self

    @sdk.app.get "/calendars" do
      content_type :json

      begin
        access_token = request.env["HTTP_AUTHORIZATION"]&.gsub(/^Bearer\s+/, "")
        raise ArgumentError, "Authorization header required" unless access_token

        calendars = extension.send(:fetch_calendars, access_token)

        status 200
        {
          success: true,
          calendars: calendars.map do |cal|
            {
              id: cal["id"],
              name: cal["summary"],
              description: cal["description"],
              timezone: cal["timeZone"],
              access_role: cal["accessRole"],
              primary: cal["primary"] || false
            }
          end
        }.to_json

      rescue ArgumentError => e
        status 401
        { success: false, error: e.message }.to_json

      rescue GoogleCalendarExtension::GoogleAPIError => e
        status e.status_code || 502
        { success: false, error: e.message }.to_json

      rescue StandardError => e
        extension.instance_variable_get(:@logger).error "Error listing calendars: #{e.message}"
        status 500
        { success: false, error: "Internal server error" }.to_json
      end
    end
  end

  def register_events_route
    extension = self

    @sdk.app.get "/calendars/:calendar_id/events" do
      content_type :json

      begin
        access_token = request.env["HTTP_AUTHORIZATION"]&.gsub(/^Bearer\s+/, "")
        raise ArgumentError, "Authorization header required" unless access_token

        calendar_id = params[:calendar_id]
        time_min = params[:time_min] || Time.now.utc.iso8601
        time_max = params[:time_max] || (Time.now.utc + (30 * 24 * 60 * 60)).iso8601

        events = extension.send(:fetch_events, access_token, calendar_id, time_min, time_max)

        status 200
        {
          success: true,
          calendar_id: calendar_id,
          events: events.map { |event| extension.send(:process_event, event, calendar_id) }
        }.to_json

      rescue ArgumentError => e
        status 401
        { success: false, error: e.message }.to_json

      rescue GoogleCalendarExtension::GoogleAPIError => e
        status e.status_code || 502
        { success: false, error: e.message }.to_json

      rescue StandardError => e
        extension.instance_variable_get(:@logger).error "Error fetching events: #{e.message}"
        status 500
        { success: false, error: "Internal server error" }.to_json
      end
    end
  end

  def register_sync_route
    extension = self

    @sdk.app.post "/sync" do
      content_type :json

      begin
        access_token = request.env["HTTP_AUTHORIZATION"]&.gsub(/^Bearer\s+/, "")
        raise ArgumentError, "Authorization header required" unless access_token

        request_body = JSON.parse(request.body.read, symbolize_names: true)

        calendar_ids = request_body[:calendar_ids] || ["primary"]
        sync_window_days = request_body[:sync_window_days] || 180

        time_min = Time.now.utc.iso8601
        time_max = (Time.now.utc + (sync_window_days * 24 * 60 * 60)).iso8601

        all_events = []
        errors = []

        calendar_ids.each do |calendar_id|
          begin
            events = extension.send(:fetch_events, access_token, calendar_id, time_min, time_max)
            processed_events = events.map { |event| extension.send(:process_event, event, calendar_id) }
            all_events.concat(processed_events)
          rescue GoogleCalendarExtension::GoogleAPIError => e
            errors << { calendar_id: calendar_id, error: e.message }
          end
        end

        status 200
        {
          success: true,
          events_synced: all_events.count,
          calendars_synced: calendar_ids.count - errors.count,
          events: all_events,
          errors: errors.presence,
          synced_at: Time.now.utc.iso8601
        }.to_json

      rescue JSON::ParserError
        status 400
        { success: false, error: "Invalid JSON in request body" }.to_json

      rescue ArgumentError => e
        status 401
        { success: false, error: e.message }.to_json

      rescue StandardError => e
        extension.instance_variable_get(:@logger).error "Error syncing calendars: #{e.message}"
        status 500
        { success: false, error: "Internal server error" }.to_json
      end
    end
  end

  # =============================================================================
  # Google Calendar API Helpers
  # =============================================================================

  def fetch_calendars(access_token)
    uri = URI("#{GOOGLE_CALENDAR_API_BASE}/users/me/calendarList")

    http_request = Net::HTTP::Get.new(uri)
    http_request["Authorization"] = "Bearer #{access_token}"

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(http_request)
    end

    unless response.is_a?(Net::HTTPSuccess)
      raise GoogleAPIError.new("Failed to fetch calendars: #{response.message}", status_code: response.code.to_i)
    end

    data = JSON.parse(response.body)
    data["items"] || []
  end

  def fetch_events(access_token, calendar_id, time_min, time_max)
    encoded_calendar_id = URI.encode_www_form_component(calendar_id)
    uri = URI("#{GOOGLE_CALENDAR_API_BASE}/calendars/#{encoded_calendar_id}/events")
    uri.query = URI.encode_www_form({
      timeMin: time_min,
      timeMax: time_max,
      singleEvents: true,
      orderBy: "startTime",
      maxResults: 2500
    })

    http_request = Net::HTTP::Get.new(uri)
    http_request["Authorization"] = "Bearer #{access_token}"

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(http_request)
    end

    unless response.is_a?(Net::HTTPSuccess)
      raise GoogleAPIError.new("Failed to fetch events: #{response.message}", status_code: response.code.to_i)
    end

    data = JSON.parse(response.body)
    data["items"] || []
  end

  def process_event(event, calendar_id)
    title = event["summary"] || "Untitled Event"
    event_type = detect_event_type(title)

    start_time = event.dig("start", "dateTime") || event.dig("start", "date")
    end_time = event.dig("end", "dateTime") || event.dig("end", "date")
    all_day = event.dig("start", "date").present?

    {
      id: event["id"],
      calendar_id: calendar_id,
      title: title,
      description: event["description"],
      location: event["location"],
      start_time: start_time,
      end_time: end_time,
      all_day: all_day,
      status: event["status"],
      event_type: event_type,
      attendees: (event["attendees"] || []).map { |a| a["email"] },
      recurring: event["recurringEventId"].present?,
      visibility: event["visibility"] || "default",
      html_link: event["htmlLink"]
    }
  end

  def detect_event_type(title)
    title_lower = title.downcase

    EVENT_TYPE_MAPPING.each do |event_type, keywords|
      return event_type if keywords.any? { |keyword| title_lower.include?(keyword) }
    end

    "meeting"
  end
end

# Start the extension when run directly
if __FILE__ == $PROGRAM_NAME
  extension = GoogleCalendarExtension.new
  extension.run!(port: ENV.fetch("PORT", 9292).to_i)
end
