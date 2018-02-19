require 'net/http'
require 'json'

module NhtsaVin
  class Query

    NHTSA_URL = 'https://vpic.nhtsa.dot.gov/api/vehicles/decodevin/'.freeze

    attr_reader :vin, :url, :response, :data, :error, :error_code, :raw_response

    def initialize(vin, options={})
      @vin = vin
      @http_options = options[:http] || {}
      build_url
    end

    def get
      @raw_response = fetch
      return if @raw_response.nil?
      begin
        parse(JSON.parse(@raw_response))
      rescue JSON::ParserError
        @valid = false
        @error = "Response is not valid JSON"
      end
    end

    def valid?
      @valid
    end

    def parse(json)
      @data = json['Results']

      # 0 - Good
      # 1 - VIN decoded clean. Check Digit (9th position) does not calculate properly.
      # 3 - VIN corrected, error in one position (assuming Check Digit is correct).
      # 5 - VIN has errors in few positions.
      # 6 - Incomplete VIN.
      # 8 - No detailed data available currently.
      # 11- Incorrect Model Year, decoded data may not be accurate!
      @error_code = value_id_for('Error Code')&.to_i
      @valid = (@error_code < 4) ? true : false

      if @error_code != 0
        @error = value_for('Error Code')
      end
      return nil unless valid?

      make = value_for('Make').capitalize
      model = value_for('Model')
      trim = value_for('Trim')
      year = value_for('Model Year')
      style = value_for('Body Class')
      type = vehicle_type(style, value_for('Vehicle Type'))
      doors = value_for('Doors')&.to_i

      @response = Struct::NhtsaResponse.new(@vin, make, model, trim, type, year,
                                            style, value_for('Vehicle Type'), doors)
    end

    def vehicle_type(body_class, type)
      return case type
      when 'PASSENGER CAR'
        'Car'
      when 'TRUCK'
        if body_class =~ /van/i
          'Van'
        else
          'Truck'
        end
      when 'MULTIPURPOSE PASSENGER VEHICLE (MPV)'
        if body_class =~ /Sport Utility/i
          'SUV'
        else
          'Minivan'
        end
      end
    end

    private

      def get_row(attr_name)
        @data.select { |r| r['Variable'] == attr_name }.first
      end

      def value_for(attr_name)
        get_row(attr_name)['Value']
      end

      def value_id_for(attr_name)
        get_row(attr_name)['ValueId']
      end

      def build_url
        @url = "#{NHTSA_URL}#{@vin}?format=json"
      end

      def fetch
        begin
          @valid = false
          url = URI.parse(@url)

          http = Net::HTTP.new(url.host, url.port)
          @http_options.each do |key, val|
            http.send("#{key}=", val)  if val
          end

          resp = http.request_get(url.path)
          case resp
            when Net::HTTPSuccess
              @valid = true
              resp.body
            when Net::HTTPRedirection
              raise "No support for HTTP redirection from NHTSA API"
            when Net::HTTPClientError
              @error = "Client error: #{resp.code} #{resp.message}"
              nil
            else
              @error = resp.message
              nil
          end

        rescue Timeout::Error, Errno::EINVAL, Errno::ECONNRESET, EOFError, SocketError,
               Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError,
               Net::ProtocolError, Errno::ECONNREFUSED => e
          @error = e.message
          nil
        end
      end
  end

  Struct.new('NhtsaResponse', :vin, :make, :model, :trim, :type, :year,
             :body_style, :vehicle_class, :doors)
end
