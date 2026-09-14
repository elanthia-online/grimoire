module Grimoire
  # Plain holder for the room fields RoomTracker populates. #enter replaces
  # every field (a real room transition); #update merges only the given
  # fields (a periodic/passive refresh) -- see docs/decisions.md "Room
  # transitions and periodic room updates are two distinct events".
  class RoomState
    attr_reader :number, :title, :description, :objects, :players, :exits

    def enter(number: nil, title: nil, description: nil, objects: nil, players: nil, exits: nil)
      @number      = number
      @title       = title
      @description = description
      @objects     = objects
      @players     = players
      @exits       = exits
    end

    def update(objects: nil, players: nil)
      @objects = objects unless objects.nil?
      @players = players unless players.nil?
    end
  end
end
