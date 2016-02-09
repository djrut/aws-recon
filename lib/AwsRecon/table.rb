module AwsRecon
  class Table
    attr_accessor :header, :footer, :tabs, :group
    MAX_ROWS = 1024
  
    def initialize(args={})
      @num_rows = args[:rows] || MAX_ROWS
      @format   = args[:format]
      @notags   = args[:notags]
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
      @col      += 1
      @col_tail = [@col,@col_tail].max
      print_debug(source: "#{__method__}", message: "New col = #{@col} tabs = #{@col_tabs} tail = #{@col_tail}") if $debug
    end

    def next_row
      @row      += 1
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
          unless attribute[:type] == :tags && @notags
            @tabs.push(attribute[:column_width])
            @header[0].push(@group)
            @header[1].push(attribute[:column_name])
            @group = ""
          end
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
          unless attribute[:type] == :tags && @notags
            if totals[attribute[:target]]
              @footer.push(totals[attribute[:target]].to_s)
            else
              @footer.push("N/A")
            end
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
