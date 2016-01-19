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
  
      attributes.each do |attribute|
        print_debug(source: "#{__method__}", message: "Parsing attribute #{attribute}") if $debug
    
        if attribute[:root_node]
          table.reset_row
          table.align_col
        end

        case attribute[:type]
        when :scalar
          if attribute[:stub]
            output = datum[attribute[:stub]][attribute[:target]]
          else
            output = datum[attribute[:target]]
          end
          table.push(data: output.to_s)
        when :boolean
          if datum[attribute[:target]]
            output = "true"
          else
            output = "false"
          end
          table.push(data: output.to_s)
        when :tags  
          tags = datum[attribute[:stub]]
          tags.each do |tag|
            output = tag.key + " = " + tag.value
            table.push(data: output.to_s)
            table.next_row
          end
        when :collection
          table.set_col_tab

          datum[attribute[:collection_name]].each do |item|
            print_debug(source: "#{__method__}", message: "Parsing item #{item}") if $debug
    
            parse_datum( datum:      item,
                         attributes: attribute[:attributes],
                         table:      table)

            table.reset_col
            table.next_row
          end
          table.strip_col_tab
        when :foreign_collection
          table.set_col_tab

          options = attribute[:options]

          options[attribute[:filter].keys[0]] = datum[attribute[:filter].values[0]]

          print_debug(source: "#{__method__}", message: "Foreign collection options #{options}") if $debug

          foreign_data = fetch_collection( client:            attribute[:client],
                                           method:            attribute[:method],
                                           options:           attribute[:options],
                                           collection_name:   attribute[:collection_name] )

          foreign_data.each_with_index do |item,index|
            print_debug(source: "#{__method__}", message: "Parsing foreign item ##{index} of #{foreign_data.size-1} contents: #{item}") if $debug
    
            parse_datum( datum:      item,
                         attributes: attribute[:attributes],
                         table:      table)
    
            table.reset_col
            table.next_row
          end
            table.strip_col_tab
        end
    
        if attribute[:sum]
          @totals[attribute[:target]] = 0 if @totals[attribute[:target]].nil?
          @totals[attribute[:target]] += output.to_i
        end

        if attribute[:count]
          @totals[attribute[:target]] = 0 if @totals[attribute[:target]].nil?
          @totals[attribute[:target]] += 1
        end

        table.next_col
      end
    end
  end

  class Table
    attr_accessor :header, :footer, :tabs, :group
    MAX_ROWS = 128
  
    def initialize(args={})
      @num_rows = args[:rows] || MAX_ROWS
      @format   = args[:format]
      @col      = 0
      @row      = 0
      @row_head = 0
      @row_tail = 0
      @col_tabs = [0] 
      @col_tail = 0
      @title    = "Empty table"
      @group    = String.new
      @header   = Array.new(2) { Array.new }
      @tabs     = Array.new
      @footer   = Array.new
      @matrix   = Array.new(@num_rows) { Array.new }
    end

    def self.formats
      ["console","csv"]
    end
  
    def next_col
      @col += 1
      @col_tail = [@col,@col_tail].max
      print_debug(source: "#{__method__}", message: "New col = #{@col} tabs = #{@col_tabs} tail = #{@col_tail}") if $debug
    end

    def next_row
      @row += 1
      @row_tail = [@row,@row_tail].max
      print_debug(source: "#{__method__}", message: "Setting next row = #{@row} tail = #{@row_tail}") if $debug
    end

    def new_row
      @row_head     = @row_tail + 1
      @row          = @row_head
      @row_tail     = @row_head
      @col          = 0
      @col_tabs     = [0]
      @col_tail     = 0
      print_debug(source: "#{__method__}", message: "Setting NEW row = #{@row} head = #{@row_head} tail = #{@row_tail} col = #{@col}") if $debug
    end
    
    def set_col_tab
      print_debug(source: "#{__method__}", message: "Setting new tab at col = #{@col} full stack: #{@col_tabs}") if $debug
      @col_tabs.push(@col)
    end

    def strip_col_tab
      print_debug(source: "#{__method__}", message: "Stripping tab at col = #{@col} full stack: #{@col_tab}") if $debug
      @col_tabs.pop
    end

    def align_col
      @col        = @col_tail
      print_debug(source: "#{__method__}", message: "Setting NEW col = #{@col} tabs = #{@col_tabs} tail = #{@col_tail} row = #{@row}") if $debug
    end

    def reset_row
      @row = @row_head
      print_debug(source: "#{__method__}", message: "New row = #{@row}") if $debug
    end

    def reset_col
      print_debug(source: "#{__method__}", message: "Resetting col to latest tab stop at col =  #{@col_tabs.last} tabs = #{@col_tabs} tail = #{@col_tail} row = #{@row}") if $debug
      @col = @col_tabs.last
    end

    def push(args={})
      print_debug(source: "#{__method__}", message: "Pushing data: \"#{args[:data]}\ to row = #{@row} col = #{@col}") if $debug
      @matrix[@row][@col] = args[:data]
    end

    def pop
      @matrix[@row][@col]
    end

    def set_title(args={})
      status  = args[:status]    
      name    = args[:name]    

      if status
        @title = "= SUMMARY for: " + name
      else
        @title = "= NO DATA for: " + name
      end
    end

    def set_header(args={})
      attributes  = args[:attributes]
  
      print_debug(source: "#{__method__}", message: "Parsing attributes array #{attributes}") if $debug
  
      attributes.each do |attribute|
        print_debug(source: "#{__method__}", message: "Parsing attribute #{attribute}") if $debug

        case attribute[:type]
        when :scalar, :boolean, :tags
          @tabs.push(attribute[:column_width])
          @header[0].push(@group)
          @header[1].push(attribute[:column_name])
          @group = ""
        when :collection, :foreign_collection
          @group = attribute[:name]
          set_header( attributes: attribute[:attributes] )
        end
      end
    end

    def set_footer(args={})
      attributes  = args[:attributes]
      totals      = args[:totals]

      attributes.each do |attribute|
        case attribute[:type]
        when :scalar, :boolean, :tags
          if totals[attribute[:target]]
            @footer.push(totals[attribute[:target]].to_s)
          else
            @footer.push("N/A")
          end
        when :collection, :foreign_collection
          set_footer( attributes: attribute[:attributes],
                      totals:     totals )
        end
      end
    end

    def render(args={})
      format = args[:format] || :console

      printf "\n"
      printf @title

      # Render the header group row
      #
      printf "\n" if !@tabs.empty?
      @tabs.each_with_index do |tab,index|
        case @format
        when :console
          printf "%-#{tab}s", @header[0][index].to_s.slice(0, tab - 1)
        when :csv
          printf "%s,", @header[0][index]
        end
      end

      # Render the header attribute row
      #
      printf "\n" if !@tabs.empty?
      @tabs.each_with_index do |tab,index|
        case @format
        when :console
          printf "%-#{tab}s", @header[1][index].to_s.slice(0, tab - 1)
        when :csv
          printf "%s,", @header[1][index]
        end
      end

      # Render the header separation row
      #
      printf "\n" if !@tabs.empty?
      @tabs.each_with_index do |tab,index|
        case @format
        when :console
          printf "%-#{tab}s", "-" * (tab - 1)
        when :csv
          printf "%s,", "-" * @header[1][index].size
        end
      end

      # Render the main table contents
      #
      printf "\n"
      @matrix.each do |row|
        if !row.empty?
          @tabs.each_with_index do |tab, index|
            case @format
            when :console
              printf "%-#{tab}s", row[index].to_s.slice(0, tab - 1)
            when :csv
              printf "%s,", row[index]
            end
          end
          printf "\n"
        end
      end

      # Render the footer separation row
      #
      @tabs.each_with_index do |tab,index|
        case @format
        when :console
          printf "%-#{tab}s", "-" * (tab - 1)
        when :csv
          printf "%s,", "-" * (tab - 1)
        end
      end

      # Render the footer row
      #
      printf "\n" if !@tabs.empty?
      @tabs.each_with_index do |tab,index|
        case @format
        when :console
          printf "%-#{tab}s", @footer[index].to_s.slice(0, tab - 1)
        when :csv
          printf "%s,", @footer[index]
        end
      end
      printf "\n"
    end
  end
end
