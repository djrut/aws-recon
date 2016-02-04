module AwsRecon
  class Service
    attr_accessor :name, :attributes, :data, :totals
  
    def initialize(args={})
      @metadata         = args[:metadata]
      @clients          = args[:clients]

      @name             = @metadata[:name]
      @attributes       = @metadata[:attributes]
      @totals           = Hash.new

      @data = fetch_collection( method:     @metadata[:method],
                                client:     @metadata[:client],
                                options:    @metadata[:options],
                                collection_name: @metadata[:collection_name] )
        print_debug(source: "#{__method__}", message: "data = #{@data}") if $debug
    end

    def fetch_collection(args={})
      client      = @clients[args[:client]]
      method      = args[:method]
      options     = args[:options]
      collection_name  = args[:collection_name]

      print_debug(source: "#{__method__}", message: "method = #{method}") if $debug
      print_debug(source: "#{__method__}", message: "options = #{options}") if $debug
      print_debug(source: "#{__method__}", message: "client = #{client}") if $debug
      print_debug(source: "#{__method__}", message: "collection = #{collection_name}") if $debug

      begin
        output = client.send(method,options)
        print_debug(source: "#{__method__}", message: "output[collection] = #{output[collection_name]}") if $debug
        print_debug(source: "#{__method__}", message: "collection = #{collection_name}") if $debug
      rescue Seahorse::Client::NetworkingError => error
        puts "Unable to establish connection: #{error.message}"
        puts "Check your network connectivity, and that the supplied region name is correct."
        exit 1
      rescue Aws::IAM::Errors::ExpiredToken => error
        puts "Temporary authentication failed: #{error.message}"
        exit 1
      rescue Aws::IAM::Errors::ServiceError => error
        puts "Operation failed: #{error.message}"
        exit 1
      else
        print_debug(source: "#{__method__}", message: "output[collection] = #{output[collection_name]}") if $debug
        print_debug(source: "#{__method__}", message: "collection = #{collection_name}") if $debug
        output[collection_name]
      end
    end

    def has_items?
      print_debug(source: "#{__method__}", message: "output class = #{@output.class}") if $debug
      @data.any?
    end

    def num_items
      @data.size
    end

    def parse_datum(args={})
      datum       = args[:datum]
      table       = args[:table]
      attributes  = args[:attributes]
      output      = String.new

      print_debug(source: "#{__method__}", message: "Parsing datum #{datum}") if $debug
      print_debug(source: "#{__method__}", message: "Parsing #{attributes.size} attributes from #{attributes}") if $debug
  
      attributes.each do |item|
        attribute = AwsRecon::Attribute.new(metadata: item)

        print_debug(source: "#{__method__}", message: "Parsing attribute #{attribute}") if $debug
    
        if attribute.is_root?
          table.reset_row
          table.align_col
        end

        case attribute.type
        when :scalar
          if attribute.stub
            output = datum[attribute.stub][attribute.target]
          else
            output = datum[attribute.target]
          end
          table.push(data: output.to_s)
        when :boolean
          if datum[attribute.target]
            output = "true"
          else
            output = "false"
          end
          table.push(data: output.to_s)
        when :tags  
          tags = datum[attribute.stub]
          tags.each do |tag|
            output = tag.key + " = " + tag.value
            table.push(data: output.to_s)
            table.next_row
          end
        when :collection
          table.set_col_tab

          datum[attribute.collection_name].each do |item|
            print_debug(source: "#{__method__}", message: "Parsing item #{item}") if $debug
    
            parse_datum( datum:      item,
                        attributes:  attribute.attributes,
                         table:      table)

            table.reset_col
            table.next_row
          end
          table.strip_col_tab
        when :foreign_collection
          table.set_col_tab

          options = attribute.build_options(datum: datum)

          print_debug(source: "#{__method__}", message: "Foreign collection options #{options}") if $debug

          foreign_data = fetch_collection( client:            attribute.client,
                                           method:            attribute.method,
                                           options:           options,
                                           collection_name:   attribute.collection_name )

          foreign_data.each_with_index do |item,index|
            print_debug(source: "#{__method__}", message: "Parsing foreign item ##{index} of #{foreign_data.size-1} contents: #{item}") if $debug
    
            parse_datum( datum:      item,
                        attributes:  attribute.attributes,
                         table:      table)
    
            table.reset_col
            table.next_row
          end
            table.strip_col_tab
        end
    
        if attribute.summed?
          @totals[attribute.target] = 0 if @totals[attribute.target].nil?
          @totals[attribute.target] += output.to_i
        end

        if attribute.counted?
          @totals[attribute.target] = 0 if @totals[attribute.target].nil?
          @totals[attribute.target] += 1
        end

        table.next_col
      end
    end
  end
end
