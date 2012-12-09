# Description:
#   Clean up your mess
#
# Dependencies:
#   "request": "2.12.0"
#   "moment": "1.7.2"
#   "underscore": "1.4.3"
#   "redis": "0.8.2"
#
# Configuration:
#   None
#
# Commands:
#   hubot schedule - Will show the previous item on the schedule
#   hubot give <amount> points to <name> - Will give the amount of points to a specific person
#   hubot top 3 - Will show the top 3 persons with the most points
#
# Author:
#   davidvanleeuwen

request = require('request')
moment  = require('moment')
{_}     = require('underscore')
redis   = require('redis')


# Enter the Campfire roomnumber that it checks
room    = 12345

schedule              = []

# Please use schedule[daynumber]['24h time']
# Example for monday:
schedule[1]           = {}
schedule[1]['9:30']   =
                        todo: (user) ->
                          "Goodmorning #{user}, can you clean out the dishwasher?"
                        points: 1
schedule[1]['12:00']  =
                        todo: (user) ->
                          "Hey #{user}, can you prepare lunch?"
                        points: 2
schedule[1]['17:00']  =
                        todo: (user) ->
                          "@#{user}: could you turn on the dishwasher and clean up the bar before you leave?"
                        points: 1





client = redis.createClient()

class Player
  constructor: (user, cb) ->
    @name   = @getKeyByName(user)
    @cid    = @name.toLowerCase()
    @user   = user
    @_data  = {}

  create: (cb) ->
    client.get "hubot:player:#{@cid}", (err, reply) =>
      unless err
        unless reply
          client.sadd 'players', "hubot:player:#{@cid}"
          @set(name: @user.name, points: 0, nickname: @name, online: true)
        else
          obj           = JSON.parse(reply)
          @_data[attr] = obj[attr] for attr of obj

        cb()

  fetch: (cb) ->
    client.get "hubot:player:#{@cid}", (err, reply) =>
      unless err
        if reply
          obj          = JSON.parse(reply)
          @_data[attr] = obj[attr] for attr of obj
          cb(null, this)
        else
          cb("Player does not exist!")

  get: (attr) ->
    return @_data[attr]

  set: (object) ->
    @_data[key] = object[key] for key of object
    client.set "hubot:player:#{@cid}", JSON.stringify(@_data)

  getKeyByName: (user) ->
    return user.name.split(" ")[0] if user.name
    return user

class Players
  constructor: ->
    @_players = {}

  get: (user, cb) ->
    if @_players[user.name]
      # Return excisting player
      cb(@_players[user.name])
    else
      # Create new player
      player = new Player(user)
      player.create =>
        @_players[player.name] = player
        cb(player)

  find: (nickname, cb) ->
    # Find player by nickname
    cached = _.find @_players, (player) -> player.get('nickname').toLowerCase() is nickname.toLowerCase()
    return cb(null, cached) if cached

    # If player not in cache, get it from the data store
    player = new Player(nickname)
    player.fetch (err) =>
      unless err
        @_players[player.name] = player
        cb(null, player)
      else
        cb(err)

  getRandom: ->
    # Returns the user with the less points in a random order
    randomized    = _.shuffle(@_players)
    onlineUsers   = _.filter @_players, (player) -> player.get('online')
    return if onlineUsers.length is 0
    _.min onlineUsers, (player) -> player.get('points')

  setToOffline: ->
    _.each @_players, (player) -> player.set(online: false)

  fetch: (cb) ->
    client.smembers 'players', (err, replies) =>
      unless err
        for cid in replies
          for player in @_players
            replies = _.without(players, player) if player.cid is cid

        cb() if replies.length is 0

        for newPlayer in replies
          client.get newPlayer, (err, reply) =>
            unless err
              data                    = JSON.parse(reply)
              player                  = new Player(data.nickname)
              player.set(data)
              @_players[player.name]  = player

              cb() if "hubot:player:#{player.cid}" is _.last(replies)

  resetOnlineStatus: (onlinePlayers) ->
    for player in @_players
      player.set(online: false) if player.get('online')

    for onlinePlayer in onlinePlayers
      for player in @_players
        if player.get('name') is onlinePlayer.name
          player.set(online: true)

  getTop: (respond) ->
    @fetch =>
      top = _.sortBy @_players, (player) -> player.get('points')
      top.reverse()
      if top.length > 3
        respond.send "1. #{top[0].get('nickname')} (#{top[0].get('points')}) \n2. #{top[1].get('nickname')} (#{top[1].get('points')}) \n3. #{top[2].get('nickname')} (#{top[2].get('points')})"
      else
        respond.send "There isn't a top 3 yet. Please try again later!"

players = new Players()


module.exports = (robot) ->
  lastTodo = "Didn't do anything yet... Go to work!"

  options = {}
  options.commands = [
    "Yes sir? I will grant you a few wishes:"
    "1) 'Hubot schedule' - Will show the previous item on the schedule"
    "2) 'Hubot give <amount> points to <name>' - Will give the amount of points to a specific person"
    "3) 'Hubot top 3' - Will show the top 3 persons with the most points"
    "\n"
    "That's it for now!"
  ]

  # Listen and change status for users
  robot.enter (log) ->
    if log.message.user.room is room
      players.get log.message.user, (player) ->
        player.set(online: true)

  robot.leave (log) ->
    if log.message.user.room is room
      players.get log.message.user, (player) ->
        player.set(online: false)

  robot.hear /^.*$/i, (msg) ->
    if msg.message.user.room is room
      players.get msg.message.user, (player) ->
        unless player.get('online')
          player.set(online: true)

  checkSchedule = ->
    now = moment()

    # Reset user status every night
    players.setToOffline() if "#{now.format('HH:mm')}" is "00:00"

    # Reset items for the next week
    if "#{now.format('HH:mm')}" is "00:00" and now.day() is 5
      for day of schedule
          for time of schedule[day]
            schedule[day][time].todo.sent = false

    # Check if something needs to be done according to the schedule and assign a user
    if schedule[now.day()]?["#{now.format('H:mm')}"]
      item = schedule[now.day()]["#{now.format('H:mm')}"]
      unless item.sent
        item.sent = true
        players.resetOnlineStatus(robot.brain.data.users)

        player = players.getRandom(robot)
        if player
          player.set(points: player.get('points')+item.points)
          lastTodo = item.todo(player.get('nickname'))
          robot.send {room: room}, lastTodo
        else
          robot.send {room: room}, '*Knock knock* Is anyone there?'

  setInterval checkSchedule, 1000
  
  robot.respond /clean$/i, (msg) ->
    msg.send options.commands.join("\n")

  robot.respond /schedule$/i, (msg) ->
    msg.send lastTodo

  robot.respond /give (\d{1,2}) (points|point) to (.*)$/i, (msg) ->
    players.get msg.message.user, (player) ->
      players.find msg.match[3], (err, otherPlayer) ->
        unless err
          if player.get('name') is otherPlayer.get('name')
            msg.send "#{player.get('nickname')}: Try throwing money at your screen. That might help!"
          else
            givingPoints = parseInt(msg.match[1])
            if (player.get('points')-givingPoints) >= 0
              otherPlayer.set(points: otherPlayer.get('points')+givingPoints)
              player.set(points: player.get('points')-givingPoints)
              if givingPoints is 0
                msg.send "#{player.get('nickname')}: Are you always that generous?"
              else
                msg.send "#{player.get('nickname')} just donated #{givingPoints} to #{otherPlayer.get('nickname')}. Current points: #{player.get('nickname')} (#{player.get('points')}) and #{otherPlayer.get('nickname')} (#{otherPlayer.get('points')})."
            else
              msg.send "#{player.get('nickname')}: You don't have enough points :("
        else
          msg.send "#{player.get('nickname')}: Not sure who you meant... Could you be more specific?"

  robot.respond /top 3$/i, (msg) ->
    players.resetOnlineStatus(robot.brain.data.users)
    players.getTop(msg)

  robot.respond /points$/i, (msg) ->
    players.get msg.message.user, (player) ->
      if player.get('points') is 1
        msg.send "#{player.get('nickname')}: You currently have #{player.get('points')} point."
      else
        msg.send "#{player.get('nickname')}: You currently have #{player.get('points')} points."
    