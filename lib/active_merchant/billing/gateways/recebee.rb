module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class RecebeeGateway < Gateway
      self.test_url = 'https://api-switcher-recebee-homolog.herokuapp.com/'
      self.live_url = 'https://api-switcher-recebee-homolog.herokuapp.com/'

      self.supported_countries = ['BR']
      self.default_currency = 'BRL'
      self.supported_cardtypes = [:visa, :master, :elo]

      self.homepage_url = 'https://recebee.com.br/'
      self.display_name = 'Recebee Gateway'

      STANDARD_ERROR_CODE_MAPPING = {}

      def initialize(options={})
        requires!(options, :access_token)
        @access_token = options[:access_token]
        @customer_id = 123

        super
      end

      def purchase(amount, payment_type, options = {})
        post = {}
        add_amount(post, amount)
        add_payment_type(post, payment_type)
        add_credit_card(post, payment_type)
        add_metadata(post, options)

        commit(:post, "/v1/customers/#{@customer_id}/transactions", post)
      end

      def authorize(amount, payment, options={})
        post = {}
        add_payment(post, payment)
        add_address(post, payment, options)
        add_customer_data(post, options)

        commit('authonly', post)
      end

      def capture(amount, authorization, options={})
        commit('capture', post)
      end

      def refund(amount, authorization, options={})
        commit('refund', post)
      end

      def void(authorization, options={})
        commit('void', post)
      end

      def verify(credit_card, options={})
        MultiResponse.run(:use_first_response) do |r|
          r.process { authorize(100, credit_card, options) }
          r.process(:ignore_result) { void(r.authorization, options) }
        end
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        #byebug # talvez devesse filtrar dados sensíveis que passam por aqui
        transcript
      end

      private

      def add_amount(post, amount)
        post[:source][:amount] = amount
      end

      def add_payment_type(post, payment_type)
        post[:payment_type] = payment_type
      end

      def add_credit_card(post, credit_card)
        post[:source][:usage] = 'single_use',
        post[:source][:type] = 'card'
        post[:source][:currency] = 'BRL'
        post[:source][:card][:card_number] = credit_card.number
        post[:source][:card][:card_holder_name] = credit_card.name
        post[:source][:card][:card_expiration_date] = "#{credit_card.month}/#{credit_card.year}"
        post[:source][:card][:card_cvv] = credit_card.verification_value
      end

      def add_metadata(post, options = {})
        post[:metadata] = {
          "payment_type": "credit",
          "description": "Switcher",
          "installment_plan": {
            "mode": "interest_free",
            "number_installments": 3
          },
          "source": {
            "usage": "single_use",
            "type": "card",
            "currency": "BRL",
            "amount": 1050,
            "card": {
              "holder_name": "Matheus Luvison",
              "expiration_month": "09",
              "expiration_year": "2024",
              "card_number": "5417319070834825",
              "security_code": "726"
            }
          }
        }
        # post[:metadata][:order_id] = options[:order_id]
        # post[:metadata][:ip] = options[:ip]
        # post[:metadata][:customer] = options[:customer]
        # post[:metadata][:invoice] = options[:invoice]
        # post[:metadata][:merchant] = options[:merchant]
        # post[:metadata][:description] = options[:description]
        # post[:metadata][:email] = options[:email]
      end

      def add_customer_data(post, options)
      end

      def add_address(post, creditcard, options)
      end

      def add_payment(post, payment)
      end

      def parse(body)
        {}
      end

      def commit(method, url, parameters, options = {})
        response = api_request(method, url, parameters, options)

        Response.new(
          success_from(response),
          message_from(response),
          response,
          authorization: authorization_from(response),
          test: test?,
          error_code: error_code_from(response)
        )
      end

      def success_from(response)
        success_purchase = response.key?('status') && response['status'] == 'succeeded'
        success_purchase
      end

      def message_from(response)
        if success_from(response)
          'Transação aprovada'
        else
          'Houve um erro ao criar a transação'
        end
      end

      def authorization_from(response)
        # este método aparentemente precisa retornar o ID da transação
        response['id'] if success_from(response)
      end

      def post_data(action, parameters = {})
      end

      def error_code_from(response)
        unless success_from(response)
          STANDARD_ERROR_CODE_MAPPING['processing_error']
        end
      end

      def api_request(method, endpoint, parameters = nil, options = {})
        raw_response = response = nil
        begin
          raw_response = ssl_request(method, self.live_url + endpoint, post_data(parameters), headers(options))
          response = parse(raw_response)
        rescue ResponseError => e
          raw_response = e.response.body
          response = response_error(raw_response)
        rescue JSON::ParserError
          response = json_error(raw_response)
        end
        response
      end

      def parse(body)
        JSON.parse(body)
      end

      def post_data(params)
        return nil unless params

        params.map do |key, value|
          next if value != false && value.blank?

          if value.is_a?(Hash)
            h = {}
            value.each do |k, v|
              h["#{key}[#{k}]"] = v unless v.blank?
            end
            post_data(h)
          elsif value.is_a?(Array)
            value.map { |v| "#{key}[]=#{CGI.escape(v.to_s)}" }.join('&')
          else
            "#{key}=#{CGI.escape(value.to_s)}"
          end
        end.compact.join('&')
      end

      def headers(options)
        headers = {
          'Content-Type' => 'application/json',
          # 'User-Agent' => "ActiveMerchantBindings/#{ActiveMerchant::VERSION}",
          'Authorization' => "Bearer #{@access_token}"
        }

        headers
      end

      def test?
        live_url.include?('homolog')
      end
    end
  end
end
