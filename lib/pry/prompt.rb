class Pry
  # Prompt represents the Pry prompt, which can be used with Readline-like
  # libraries. It defines a few default prompts (default prompt, simple prompt,
  # etc) and also provides an API for adding and implementing custom prompts.
  #
  # @example Registering a new Pry prompt
  #   Pry::Prompt.add(
  #     :ipython,
  #     'IPython-like prompt', [':', '...:']
  #   ) do |_context, _nesting, _pry_, sep|
  #     sep == ':' ? "In [#{_pry_.input_ring.count}]: " : '   ...: '
  #   end
  #
  #   # Produces:
  #   # In [3]: def foo
  #   #    ...:   puts 'foo'
  #   #    ...: end
  #   # => :foo
  #   # In [4]:
  #
  # @example Manually instantiating the Prompt class
  #   prompt_procs = [
  #     proc { '#{rand(1)}>" },
  #     proc { "#{('a'..'z').to_a.sample}*" }
  #   ]
  #   prompt = Pry::Prompt.new(
  #     :random,
  #     'Random number or letter prompt.',
  #     prompt_procs
  #   )
  #   prompt.wait_proc.call(...) #=>
  #   prompt.incomplete_proc.call(...)
  #
  # @since v0.11.0
  # @api public
  class Prompt
    # @return [String]
    DEFAULT_NAME = 'pry'.freeze

    # @return [Array<Object>] the list of objects that are known to have a
    #   1-line #inspect output suitable for prompt
    SAFE_CONTEXTS = [String, Numeric, Symbol, nil, true, false].freeze

    # A Hash that holds all prompts. The keys of the Hash are prompt
    # names, the values are Hash instances of the format {:description, :value}.
    @prompts = {}

    class << self
      # Retrieves a prompt.
      #
      # @example
      #   Prompt[:my_prompt]
      #
      # @param [Symbol] name The name of the prompt you want to access
      # @return [Hash{Symbol=>Object}]
      # @since v0.12.0
      def [](name)
        @prompts[name.to_s]
      end

      # @return [Hash{Symbol=>Hash}] the duplicate of the internal prompts hash
      # @note Use this for read-only operations
      # @since v0.12.0
      def all
        @prompts.dup
      end

      # Adds a new prompt to the prompt hash.
      #
      # @param [Symbol] name
      # @param [String] description
      # @param [Array<String>] separators The separators to differentiate
      #   between prompt modes (default mode and class/method definition mode).
      #   The Array *must* have a size of 2.
      # @yield [context, nesting, _pry_, sep]
      # @yieldparam context [Object] the context where Pry is currently in
      # @yieldparam nesting [Integer] whether the context is nested
      # @yieldparam _pry_ [Pry] the Pry instance
      # @yieldparam separator [String] separator string
      # @return [nil]
      # @raise [ArgumentError] if the size of `separators` is not 2
      # @raise [ArgumentError] if `prompt_name` is already occupied
      # @since v0.12.0
      def add(name, description = '', separators = %w[> *])
        name = name.to_s

        unless separators.size == 2
          raise ArgumentError, "separators size must be 2, given #{separators.size}"
        end

        if @prompts.key?(name)
          raise ArgumentError, "the '#{name}' prompt was already added"
        end

        @prompts[name] = new(
          name,
          description,
          separators.map do |sep|
            proc { |context, nesting, _pry_| yield(context, nesting, _pry_, sep) }
          end
        )

        nil
      end
    end

    # @return [String]
    attr_reader :name

    # @return [String]
    attr_reader :description

    # @return [Array<Proc>] the array of procs that hold
    #   `[wait_proc, incomplete_proc]`
    attr_reader :prompt_procs

    # @param [String] name
    # @param [String] description
    # @param [Array<Proc>] prompt_procs
    def initialize(name, description, prompt_procs)
      @name = name
      @description = description
      @prompt_procs = prompt_procs
    end

    # @return [Proc] the proc which builds the wait prompt (`>`)
    def wait_proc
      @prompt_procs.first
    end

    # @return [Proc] the proc which builds the prompt when in the middle of an
    #   expression such as open method, etc. (`*`)
    def incomplete_proc
      @prompt_procs.last
    end

    # @deprecated Use a `Pry::Prompt` instance directly
    def [](key)
      key = key.to_s
      loc = caller_locations(1..1).first

      if %w[name description].include?(key)
        warn(
          "#{loc.path}:#{loc.lineno}: warning: `Pry::Prompt[:#{@name}][:#{key}]` " \
          "is deprecated. Use `#{self.class}##{key}` instead"
        )
        public_send(key)
      elsif key.to_s == 'value'
        warn(
          "#{loc.path}:#{loc.lineno}: warning: `#{self.class}[:#{@name}][:value]` " \
          "is deprecated. Use `#{self.class}#prompt_procs` instead or an " \
          "instance of `#{self.class}` directly"
        )
        @prompt_procs
      end
    end

    add(
      :default,
      "The default Pry prompt. Includes information about the current expression \n" \
      "number, evaluation context, and nesting level, plus a reminder that you're \n" \
      'using Pry.'
    ) do |context, nesting, _pry_, sep|
      format(
        "[%<in_count>s] %<name>s(%<context>s)%<nesting>s%<separator>s ",
        in_count: _pry_.input_ring.count,
        name: _pry_.config.prompt_name,
        context: Pry.view_clip(context),
        nesting: (nesting > 0 ? ":#{nesting}" : ''),
        separator: sep
      )
    end

    add(
      :simple,
      "A simple `>>`.",
      ['>> ', ' | ']
    ) do |_, _, _, sep|
      sep
    end

    add(
      :nav,
      "A prompt that displays the binding stack as a path and includes information \n" \
      "about #{Helpers::Text.bold('_in_')} and #{Helpers::Text.bold('_out_')}.",
      %w[> *]
    ) do |_context, _nesting, _pry_, sep|
      tree = _pry_.binding_stack.map { |b| Pry.view_clip(b.eval('self')) }
      format(
        "[%<in_count>s] (%<name>s) %<tree>s: %<stack_size>s%<separator>s ",
        in_count: _pry_.input_ring.count,
        name: _pry_.config.prompt_name,
        tree: tree.join(' / '),
        stack_size: _pry_.binding_stack.size - 1,
        separator: sep
      )
    end

    add(
      :shell,
      'A prompt that displays `$PWD` as you change it.',
      %w[$ *]
    ) do |context, _nesting, _pry_, sep|
      format(
        "%<name>s %<context>s:%<pwd>s %<separator>s ",
        name: _pry_.config.prompt_name,
        context: Pry.view_clip(context),
        pwd: Dir.pwd,
        separator: sep
      )
    end

    add(
      :none,
      'Wave goodbye to the Pry prompt.',
      Array.new(2)
    ) { '' }
  end
end
