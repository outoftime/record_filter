module RecordFilter
  class Filter

    delegate :inspect, :to => :loaded_data

    NON_DELEGATE_METHODS = %w(debugger nil? send object_id class extend find respond_to? first last)
    [].methods.each do |m|
      unless m =~ /^__/ || NON_DELEGATE_METHODS.include?(m.to_s)
        delegate m, :to => :loaded_data
      end
    end

    def initialize(clazz, named_filter, combine_conjunction, *args, &block)
      @current_scoped_methods = clazz.send(:current_scoped_methods)
      @clazz = clazz

      @dsl = dsl_for_named_filter(@clazz, named_filter)
      @dsl.instance_eval(&block) if block
      @dsl.send(named_filter, *args) if named_filter && @dsl.respond_to?(named_filter)
      @dsl.conjunction.steps.unshift(combine_conjunction.steps).flatten! if combine_conjunction
      @query = Query.new(@clazz, @dsl.conjunction)
    end

    def first(*args)
      if args.first.kind_of?(Integer)
        loaded_data.first(*args)
      else
        do_with_scope do
          @clazz.find(:first, *args)
        end
      end
    end

    def last(*args)
      if args.first.kind_of?(Integer)
        loaded_data.last(*args)
      else
        do_with_scope do
          @clazz.find(:last, *args)
        end
      end
    end

    def filter(&block)
      Filter.new(@clazz, nil, @dsl.conjunction, &block)
    end

    def method_missing(method, *args, &block)
      if @clazz.named_filters.include?(method)
        do_with_scope do
          Filter.new(@clazz, method, @dsl.conjunction, *args)
        end
      else
        do_with_scope([:size, :length, :count].include?(method)) do
          @clazz.send(method, *args, &block)
        end
      end
    end

    def do_with_scope(for_count=false, &block)
      params = proxy_options(for_count)
      @clazz.send(:with_scope, { :find => params, :create => params }, :reverse_merge) do
        if @current_scoped_methods
          @clazz.send(:with_scope, @current_scoped_methods) do
            block.call
          end
        else
          block.call
        end
      end
    end

    def proxy_options(for_count=false) 
      @query.to_find_params(for_count)
    end

    protected

    def dsl_for_named_filter(clazz, named_filter)
      return DSL::DSL.create(clazz) if named_filter.blank?
      while (clazz)
        dsl = DSL::DSL::SUBCLASSES.has_key?(clazz.name.to_sym) ? DSL::DSL::SUBCLASSES[clazz.name.to_sym] : nil
        return DSL::DSL.create(clazz) if dsl && dsl.instance_methods(false).include?(named_filter.to_s)
        clazz = clazz.superclass
      end
      nil
    end

    def loaded_data
      do_with_scope do
        @clazz.find(:all)
      end
    end
  end
end
