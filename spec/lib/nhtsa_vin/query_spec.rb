require 'spec_helper'

describe NhtsaVin::Query do
  let(:client) { NhtsaVin::Query.new('2G1WT57K291223396') }

  let(:success_response) { File.read(File.join('spec', 'fixtures', 'success.json')) }
  let(:not_found_response) { File.read(File.join('spec', 'fixtures', 'not_found.json')) }

  describe '#initialize' do
    it 'stores the complete URL of the request' do
      expect(client.url)
        .to eq 'https://vpic.nhtsa.dot.gov/api/vehicles/decodevin/2G1WT57K291223396?format=json'
    end
  end

  describe '#get' do
    context 'successful response' do
      before do
        allow(client).to receive(:fetch).and_return(success_response)
        client.get
      end
      it 'fetches json and response is valid' do
        expect(client.raw_response).to eq success_response
        expect(client.valid?).to be true
      end
      it 'has no error' do
        expect(client.error).to be_nil
      end
      it 'has an error code of 0' do
        expect(client.error_code).to eq 0
      end
      context 'its response' do
        let(:response) { client.get }
        it 'returns a struct' do
          expect(response.class).to be Struct::NhtsaResponse
        end
        it 'returns the correct vehicle data' do
          expect(response.year).to eq '2004'
          expect(response.make).to eq 'Cadillac'
          expect(response.model).to eq 'SRX'
          expect(response.body_style).to eq 'Wagon'
          expect(response.doors).to eq 4
        end
        it 'parses out the type enumeration' do
          expect(response.type).to eq 'Minivan'
        end
      end
    end

    context 'error response' do
      before do
        allow(client).to receive(:fetch).and_return(not_found_response)
        client.get
      end
      it 'fetches json and response is not valid' do
        expect(client.raw_response).to eq not_found_response
        expect(client.valid?).to be false
      end
      it 'returns nil' do
        expect(client.get).to be_nil
      end
      it 'has an error message' do
        expect(client.error).to eq '11- Incorrect Model Year, decoded data may not be accurate!'
      end
      it 'has an error code' do
        expect(client.error_code).to eq 11
      end
    end
    context 'invalid response format' do
      before do
        allow(client).to receive(:fetch).and_return('This is not JSON')
        client.get
      end
      it 'is not valid' do
        expect(client).not_to be_valid
      end
      it 'has an error message' do
        expect(client.error).to eq 'Response is not valid JSON'
      end
    end
    context 'timeout response' do
      before do
        allow(client).to receive(:fetch).and_return('{"Count":0,"Message":"Execution Error","SearchCriteria":null,"Results":[{"Message":"Error encountered retrieving data: Connection Timeout Expired.  The timeout period elapsed while attempting to consume the pre-login handshake acknowledgement.  This could be because the pre-login handshake failed or the server was unable to respond back in time.  The duration spent while attempting to connect to this server was - [Pre-Login] initialization=6; handshake=14988; "}]}')
        client.get
      end
      it 'is not valid' do
        expect(client).not_to be_valid
        expect(client.error).to match /connection timeout expired/i
      end
    end
    context 'HTTP error' do
      it '5xx' do
        resp = Net::HTTPServerError.new(1.1, 503, 'Service unhappy')
        allow_any_instance_of(Net::HTTP).to receive(:request).and_return(resp)
        client.get
        expect(client).not_to be_valid
        expect(client.error).to eq 'Service unhappy'
      end
    end
    context 'connection or network error' do
      before do
        allow_any_instance_of(Net::HTTP).to receive(:request).and_raise(Net::ReadTimeout)
        client.get
      end
      it 'should not raise' do
        expect { client.get }.to_not raise_error
      end
      it 'should return nil' do
        expect(client.get).to be_nil
      end
      it 'should not be valid' do
        expect(client.valid?).to be false
      end
      it 'should have an error message' do
        expect(client.error).to eq 'Net::ReadTimeout'
      end
      it 'should not contain a response object' do
        expect(client.response).to be_nil
      end
    end
  end

  describe '#vehicle_type' do
    let(:query) { NhtsaVin::Query.new('') }
    context 'with type of TRUCK' do
      it 'returns van when the type is truck and body_class includes Van' do
        expect(query.vehicle_type('Cargo Van', 'TRUCK')).to eq 'Van'
      end
      it 'returns truck otherwise' do
        expect(query.vehicle_type('Light Duty Pickup', 'TRUCK')).to eq 'Truck'
      end
    end
    context 'with type MULTIPURPOSE PASSENGER VEHICLE (MPV)' do
      it 'returns SUV when the body class supports it' do
        expect(
          query.vehicle_type('Sport Utility Vehicle (SUV)',
                             'MULTIPURPOSE PASSENGER VEHICLE (MPV)')
          ).to eq 'SUV'
      end
    end
  end
end
