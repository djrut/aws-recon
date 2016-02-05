module AwsRecon
  class Attribute
    attr_accessor :column_name, :type, :target, :column_width, :stub, :column_width, :count, :sum, :collection_name, :client, :method, :options, :attributes 
  
    def initialize(args={})
      @metadata         = args[:metadata]
      @column_name      = @metadata[:column_name]
      @type             = @metadata[:type]
      @root_node        = @metadata[:root_node]
      @leaf_node        = @metadata[:leaf_node]
      @target           = @metadata[:target]
      @stub             = @metadata[:stub]
      @column_width     = @metadata[:column_width]
      @count            = @metadata[:count]
      @sum              = @metadata[:sum]
      @collection_name  = @metadata[:collection_name]
      @client           = @metadata[:client]
      @method           = @metadata[:method]
      @options          = @metadata[:options]
      @attributes       = @metadata[:attributes]
    end

    def is_root?
      @root_node
    end

    def is_leaf?
      @leaf_node
    end
    
    def counted?
      @count
    end

    def summed?
      @sum
    end
    
    def build_options(args={})
      datum = args[:datum]
      output = Hash.new

      options.each do |option|
        case option[:type]
        when :literal
          output[option[:key]] = option[:value]
        when :mapped
          if option[:array]
            output[option[:key]] = [datum[option[:value]]] 
          else
            output[option[:key]] = datum[option[:value]]
          end
        end
      end
      print_debug(source: "#{__method__}", message: "Built options = #{output}") if $debug
      return output
    end
  end
end