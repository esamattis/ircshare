fs = require "fs"

kue = require "kue"
redis = require "redis"
irc = require "irc"
_  = require 'underscore' 
_.mixin require 'underscore.string' 

urlsortener = require "./urlsortener"
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
        @client.say chan, "IRCShare.com is online on #{ @networkName }"
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
        console.log "getting user id for", share.data
        userid = @userId(share.data.nick, share.data.deviceid)

        db.get userid, (err, registered) =>
          if registered is "ok"
            @sayAndPart share.data.channel, msg, ->
              console.log "done", msg
              done()
              share.set status: "posted"
          else if registered is "no"
            done()
            share.set status: "owner refused posting"
            return
          else
            done new Error "#{ userid  } is not registered yet. Device #{ share.data.devicename }"
            @askToRegister share
            share.set status: "Asking for confirmation from #{ share.data.nick }"


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





