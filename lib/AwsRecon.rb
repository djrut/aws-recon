module AwsRecon
  class Service
    attr_accessor :name, :attributes, :describe_output, :totals
  
    def initialize(args={})
      @metadata         = args[:metadata]
      @clients          = args[:clients]

      @name             = @metadata[:name]
      @attributes       = @metadata[:attributes]
      @collection       = @metadata[:collection_name]
      @describe_method  = @metadata[:describe_method]
      @describe_options = @metadata[:describe_options]
      @client           = @clients[@metadata[:client]] 
      @totals           = { count: 0 }
      fetch_collection
    end

    def fetch_collection
      begin
        @describe_output = @client.send(@describe_method,@describe_options)
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
        @describe_output[@collection]
      end
    end

    def has_items?
      @describe_output[@collection].any?
    end

    def num_items
      @describe_output[@collection].size
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
    
        table.reset_row if attribute[:root_node]

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
          datum[attribute[:collection_name]].each do |item|
            print_debug(source: "#{__method__}", message: "Parsing item #{item}") if $debug
    
            parse_datum( datum:      item,
                         attributes: attribute[:attributes],
                         table:      table)
    
            table.next_row if attribute[:leaf_node]
          end
        end
    
        if attribute[:sum]
          @totals[attribute[:target]] = 0 if @totals[attribute[:target]].nil?
          @totals[attribute[:target]] += output.to_i
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
      @head     = 0
      @tail     = 0
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
    end

    def next_row
      @row += 1
      @tail = [@row,@tail].max
    end

    def new_row
      @head = @tail + 1
      @row  = @head
      @tail = @head
      @col  = 0
    end

    def reset_row
      @row = @head
    end

    def push(args={})
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
        when :collection
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
          if attribute[:count]
            @footer.push(totals[:count].to_s)
          elsif totals[attribute[:target]]
            @footer.push(totals[attribute[:target]].to_s)
          else
            @footer.push("N/A")
          end
        when :collection
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
