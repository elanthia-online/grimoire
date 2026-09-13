require_relative 'tokenizer'
require_relative 'room_state'

module Grimoire
  # Watches the token stream for the two distinct room-state events
  # confirmed against real traffic (see docs/decisions.md): a move-triggered
  # transition -- <nav rm='..'/> plus a clearStream/pushStream id='room'/
  # compDef bracket, which replaces every field via RoomState#enter -- and a
  # periodic/passive update -- a bare <component id='room objs'|'room
  # players'>, outside that bracket, which merges only the named field via
  # RoomState#update. Reports whether the current token is part of either
  # event, so NarrativeStream can keep this content out of the scrollback
  # pane the same way it already keeps pushStream/popStream content out.
  class RoomTracker
    Routed = Data.define(:token, :captured) do
      def narrative?
        !captured
      end
    end

    ENTER_FIELDS = {
      'room desc'    => :description,
      'room objs'    => :objects,
      'room players' => :players,
      'room exits'   => :exits,
    }.freeze

    UPDATE_FIELDS = {
      'room objs'    => :objects,
      'room players' => :players,
    }.freeze

    attr_reader :room_state

    def initialize(room_state: RoomState.new)
      @room_state     = room_state
      @in_room_stream = false
      @pending        = {}
      @current_field  = nil
      @buffer         = String.new
      @staged_number  = nil
      @staged_title   = nil
    end

    def route(token)
      handle(token)
      Routed.new(token: token, captured: !@current_field.nil?)
    end

    private

    def handle(token)
      return handle_text(token) if token.is_a?(Tokenizer::Tokens::Text)

      case token.name
      when 'nav' then stage_number(token)
      when 'streamWindow' then stage_title(token)
      when 'pushStream' then open_room_stream(token)
      when 'popStream' then close_room_stream if @in_room_stream
      when 'compDef' then handle_compdef(token)
      when 'component' then handle_component(token)
      end
    end

    def handle_text(token)
      @buffer << token.value if @current_field
    end

    def stage_number(token)
      @staged_number = token.attrs['rm']
    end

    def stage_title(token)
      return unless token.attrs['id'] == 'room'

      @staged_title = token.attrs['subtitle']&.sub(/\A\s*-\s*/, '')
    end

    def open_room_stream(token)
      return unless token.attrs['id'] == 'room'

      @in_room_stream = true
      @pending = {}
    end

    def close_room_stream
      finalize_field(@pending)
      @room_state.enter(number: @staged_number, title: @staged_title, **@pending)
      @in_room_stream = false
      @pending = {}
    end

    def handle_compdef(token)
      if token.closing
        finalize_field(@pending) if @in_room_stream
      elsif @in_room_stream
        field = ENTER_FIELDS[token.attrs['id']]
        start_field(field) if field
      end
    end

    def handle_component(token)
      return if @in_room_stream # real traffic never nests these; guard anyway

      if token.closing
        finalize_component
      else
        field = UPDATE_FIELDS[token.attrs['id']]
        start_field(field) if field
      end
    end

    def finalize_component
      return unless @current_field

      field = @current_field
      value = @buffer
      @current_field = nil
      @room_state.update(**{ field => value })
    end

    def start_field(field)
      @current_field = field
      @buffer = String.new
    end

    def finalize_field(target)
      return unless @current_field

      target[@current_field] = @buffer
      @current_field = nil
    end
  end
end
