fs = require "fs"

kue = require "kue"
redis = require "redis"
irc = require "irc"
winston = require "winston"
_  = require 'underscore' 
_.mixin require 'underscore.string' 

urlshortener = require "./urlshortener"
{ShareItem} = require "./shareitem"

config = JSON.parse fs.readFileSync "./config.json"

conn = require "./redisconnection"
kue.redis.createClient = conn.getClient


jobs = kue.createQueue()
db = jobs.client

retry = (id, cb) ->
  kue.Job.get id, (err, job) ->
    return cb err if err
    job.inactive()
    job.attempt ->
      job.update (err) ->
        cb err, job
        winston.info  "retrying job", id, job.type

retryAll = (ids) ->
  id = ids.pop()
  return if not id?
  retry id, (err) ->
    return winston.error("Failed to retry job #{ id }", err) if err
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
      winston.info  "Connected to #{ @networkName } (#{ @address })"

    @client.on "registered", =>
      winston.info  "Registered to #{ @networkName } (#{ @address })"
      @registered = true
      @startJobProcessor()
      chan = "#ircshare.com"
      @client.join chan, =>
        winston.info  "joined #{ chan }@#{ @networkName }"
        @client.say chan, "IRCShare.com is online on #{ @networkName }"
        @retryJobs()



    @client.on "pm", (from, msg) =>
      msg = _.clean msg
      [cmd, deviceid] = msg.split(" ")
      userid = @userId from, deviceid
      if cmd is "ok"
        db.set userid, "ok", (err) =>
          return winston.error("Failed to set userid #{ userid }", err) if err
          @client.say from, "Thanks! I won't ask about this again on this network and with that device."
          winston.info "#{ from }@#{ @networkName } confirmed ircshare"
          @retryJobs()
      if cmd is "no"
        db.set userid, "no", =>
          @client.say from, "Roger. I won't bother you again about this device and network."
          winston.info "#{ from }@#{ @networkName } denied posting from #{ deviceid }"

    @client.on "error", (err) ->
      winston.error "Random IRC error", err

  retryJobs: ->
    jobs.failed (err, ids) ->
      return winston.error("Failed to retry #{ ids }", err) if err
      retryAll ids

  userId: (nick, deviceid) ->
    "reg:#{ nick.toLowerCase() }@#{ @networkName }:#{ deviceid }"

  askToRegister: (share) ->
    nick = share.data.nick
    data = share.data
    @client.say nick, "Hi!"
    @client.say nick, "Somebody is trying to post a picture from
 #{ data.devicename } (#{ share.getUrl() }) to #{ data.channel } as you."
    @client.say nick, "This nickname is not registered with that device on IRCShare"
    @client.say nick, "If this is you, respond to me with: \"ok #{ data.deviceid }\" without the quotes."
    @client.say nick, "If this is not you, respond with: \"no #{ data.deviceid }\"."

  startJobProcessor: ->
    jobs.process "irc-#{ @networkName }", (job, done) =>
      share = new ShareItem id: job.data.shareId, config: config
      share.load (err) =>
        return done err if err

        msg =   "<#{ share.data.nick }> #{ share.data.caption } #{ share.getUrl()}"
        userid = @userId(share.data.nick, share.data.deviceid)

        db.get userid, (err, registered) =>
          if registered is "ok"
            @sayAndPart share.data.channel, msg, =>
              done()
              share.set status: "posted"
              @client.say share.data.nick, "Just posted #{ share.getUrl() } to #{ share.data.channel }"
              winston.info "#{ share.data.nick } posted #{ share.getUrl() } to #{ share.data.channel } @ #{ @networkName }"
          else if registered is "no"
            done()
            share.set status: "owner refused posting"
            winston.info "#{ share.data.nick }@#{ @networkName } has refused posting from #{ share.data.deviceid }"
            return
          else
            done new Error "#{ userid  } is not registered yet. Device #{ share.data.devicename }"
            winston.info "Asking confirmation from #{ share.data.nick }@#{ @networkName }"
            share.set status: "Asking for confirmation from #{ share.data.nick }"
            @askToRegister share


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





