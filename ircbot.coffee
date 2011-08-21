fs = require "fs"

kue = require "kue"
redis = require "redis"
irc = require "irc"
_  = require 'underscore' 
_.mixin require 'underscore.string' 

urlsortener = require "./urlsortener"

config = JSON.parse fs.readFileSync "./config.json"

kue.redis.createClient = ->
  client = redis.createClient(config.redis.port, config.redis.host)
  if config.redis.pass?
    client.auth config.redis.pass
  client

jobs = kue.createQueue()
db = jobs.client

retry = (id, cb) ->
  kue.Job.get id, (err, job) ->
    return cb err if err
    job.inactive()
    job.attempt ->
      job.update (err) ->
        cb err, job
        console.log "retrying job", id, job.type

retryAll = (ids) ->
  id = ids.pop()
  return if not id?
  retry id, (err) ->
    throw err if err
    retryAll ids

class IRCPoster
  constructor: (@networkName, @address) ->
    @networkName = @networkName.toLowerCase()
    nick = config.botnick
    @registered = false

    @client = new irc.Client @address, nick,
      userName: nick
      realName: "http://ircshare.com/"
      autoConnect: false
      floodProtection: true
    @client.on "connect", =>
      console.log "Connected to #{ @networkName } (#{ @address })"

    @client.on "registered", =>
      console.log "Registered to #{ @networkName } (#{ @address })"
      @registered = true
      @startJobProcessor()
      chan = "#ircshare.com"
      @client.join chan, =>
        console.log "joined #{ chan }"
        for i in [1..20]
          @client.say chan, "#{ i }. IRCShare.com is online on #{ @networkName }"
        @retryJobs()


    @client.on "message", (from, to, msg) =>
      console.log from, msg, to

    @client.on "pm", (from, msg) =>
      msg = _.clean msg
      [cmd, deviceid] = msg.split(" ")
      userid = @userId from, deviceid
      if cmd is "ok"
        db.set userid, "ok", (err) =>
          throw err if err
          @client.say from, "Thanks! I won't ask about this again on this network and with that device."
          @retryJobs()
      if cmd is "no"
        db.set userid, "no", =>
          @client.say from, "Roger. I won't bother you again about this device and network."

    @client.on "error", (err) ->
      console.log "IRC ERRIR", err

  retryJobs: ->
    jobs.failed (err, ids) ->
      throw err if err
      retryAll ids

  userId: (nick, deviceid) ->
    "reg:#{ nick }@#{ @networkName }:#{ deviceid }"

  askToRegister: (nick, data) ->
    @client.say nick, "Hi!"
    @client.say nick, "Somebody is trying to post a picture from 
 #{ data.devicename } with caption \" #{ data.caption }\" to #{ data.channel } as you."
    @client.say nick,  "This nickname is not registered with that device on IRCShare.com."
    @client.say nick, "If this is you, respond to me with: \"ok #{ data.deviceid }\" without the quotes."
    @client.say nick, "If this is not you, respond with: \"no #{ data.deviceid }\"."

  startJobProcessor: ->
    jobs.process "irc-#{ @networkName }", (job, done) =>

      msg =   "<#{ job.data.nick }> #{ job.data.caption } #{ config.domain }#{ urlsortener.encode job.id }"
      userid = @userId(job.data.nick, job.data.deviceid)

      db.get userid, (err, registered) =>
        console.log "process", err, registered
        if registered is "ok"
          console.log "SAYING", job.data.channel
          @sayAndPart job.data.channel, msg, ->
            console.log "done", msg
            done()
        else if registered is "no"
          done()
          return
        else
          done new Error "#{ userid  } is not registered yet. Device #{ job.data.devicename }"
          @askToRegister job.data.nick, job.data


  start: ->
    @client.connect()

  sayAndPart: (channel, msg, cb) ->
    msg = msg.replace "\n", " "
    if /^[#!‚]/.test channel
      @client.join channel, =>
        @client.say channel, msg
        @client.part channel, cb
    else
        @client.say channel, msg
        cb?()



# setTimeout ->
#   jobs.failed (err, ids) ->
#     throw err if err
#     retryAll ids
# , 2000


for network in config.irc
  new IRCPoster(network.name, network.host).start()





