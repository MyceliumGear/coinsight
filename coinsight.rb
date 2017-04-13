require 'json'
require 'uri'
require 'rack-app'
require 'faraday'

class Coinsight < Rack::App

  INSIGHT_API = ENV['INSIGHT_API'] || 'http://localhost/api'

  def float_to_satoshi(float)
    (float.to_f * 1e8).to_i
  end

  def insight(method, path, body: nil, params: nil)
    begin
      conn     = Faraday.new(
        url:     "#{INSIGHT_API}#{path}",
        params:  params,
        headers: { 'Content-Type' => 'application/json' },
        ssl:     { verify: true }
      ) do |faraday|
        faraday.adapter :net_http
      end
      response =
        case method
        when :get
          conn.get
        when :post
          conn.post do |req|
            req.body = body
          end
        else
          raise "Unknown method: #{method.inspect}"
        end
    rescue => ex
      $stderr.puts ex.inspect
      raise ex
    end
    begin
      JSON(response.body.to_s)
    rescue
      $stderr.puts response.inspect
      raise response.body.to_s
    end
  end

  get '/v1/addresses/:address/transactions' do
    begin
      results      = []
      transactions = []
      address      = insight(:get, "/addr/#{params['address']}")

      # limit transactions number to retrieve
      if params['filter'] != 'all'
        # Openchain only interested in the unconfirmed transaction, and timeouts fast
        if address['unconfirmedTxApperances'] > 0
          # lets find at least one unconfirmed transaction
          address['transactions'].reverse_each do |tid|
            transaction = insight(:get, "/tx/#{tid}")
            transactions.unshift transaction
            break if transaction['blockhash'].to_s.empty?
          end
        end
      else
        transactions = address['transactions'].map { |tid| insight(:get, "/tx/#{tid}") }
      end

      transactions.each do |transaction|
        inputs = []
        transaction['vin'].each do |input|
          inputs << {
            transaction_hash: transaction['txid'],
            output_hash:      input['txid'],
            output_index:     input['vout'],
            value:            input['valueSat'],
            addresses:        [input['addr']].flatten,
            script_signature: (input['scriptSig']['hex'] rescue nil),
          }
        end
        outputs = []
        transaction['vout'].each do |output|
          outputs << {
            transaction_hash: transaction['txid'],
            index:            output['n'],
            value:            float_to_satoshi(output['value']),
            addresses:        (output['scriptPubKey']['addresses'] rescue nil),
            script:           (output['scriptPubKey']['hex'] rescue nil),
          }
        end
        results << {
          hash:          transaction['txid'],
          block_hash:    transaction['blockhash'].to_s.empty? ? nil : transaction['blockhash'],
          block_height:  transaction['blockheight'],
          block_time:    (Time.at(transaction['blocktime']).utc.to_s rescue nil),
          inputs:        inputs,
          outputs:       outputs,
          amount:        float_to_satoshi(transaction['valueOut']),
          fees:          float_to_satoshi(transaction['fees']),
          confirmations: transaction['confirmations'],
        }
      end

      JSON(results)
    rescue => ex
      response.status = 500
      JSON(error: ex.message)
    end
  end

  get '/v1/addresses/:address/unspents' do
    begin
      results = []
      address = insight(:get, "/addr/#{params['address']}/utxo")
      address.each do |output|
        results << {
          transaction_hash: output['txid'],
          output_index:     output['vout'],
          value:            float_to_satoshi(output['amount']),
          addresses:        [output['address']].flatten,
          script_hex:       output['scriptPubKey'],
          spent:            false
        }
      end

      JSON(results)
    rescue => ex
      response.status = 500
      JSON(error: ex.message)
    end
  end

  post '/v1/sendrawtransaction' do
    begin
      $stderr.puts "TX to broadcast: #{payload.inspect}"
      body = JSON(rawtx: payload.gsub('"', ''))
      result = insight(:post, '/tx/send', body: body)
      $stderr.puts "Result: #{result.inspect}"
      result['txid'].inspect
    rescue => ex
      response.status = 500
      JSON(error: ex.message)
    end
  end
end
