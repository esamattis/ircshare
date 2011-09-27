fs = require "fs"
path = require "path"
qs = require "querystring"

express = require "express"
cluster = require "cluster"
redis = require "redis"
form = require "connect-form"
stylus = require "stylus"
nib = require "nib"
kue = require "kue"
winston = require "winston"


_  = require 'underscore'
_.mixin require 'underscore.string'

piles = require "piles"
js = piles.createJSManager()
css = piles.createCSSManager()

addCodeSharingTo = require("express-share").addCodeSharingTo

urlshortener = require "./urlshortener"
{ShareItem} = require "./shareitem"

config = JSON.parse fs.readFileSync "./config.json"

conn = require "./redisconnection"
kue.redis.createClient = conn.getClient

kueui = express.createServer()
kueui.use(express.basicAuth(config.kueui.user, config.kueui.pass))
kueui.use kue.app


jobs = kue.createQueue()
db = jobs.client

app = express.createServer()

app.configure ->
  app.use form
    keepExtensions: true
    uploadDir: __dirname + '/public/img'
  app.use express.static __dirname + '/public'

  app.use stylus.middleware
    force: true
    src: __dirname + "/public"
    compile: (str, path) ->
      stylus(str).set("filename", path).use(nib())

  js.bind app
  css.bind app

  css.addFile __dirname + "/public/main.styl"
  css.addFile __dirname + "/public/bootstrap-1.0.0.css"

  js.addFile  __dirname + "/client/vendor/jquery.js"
  js.addFile  __dirname + "/client/vendor/underscore.js"
  js.addFile  __dirname + "/client/vendor/backbone.js"
  js.addFile  __dirname + "/client/vendor/dumbformstate.js"
  js.addFile  __dirname + "/client/jquery.edited.coffee"
  js.addFile  __dirname + "/client/main.coffee"

app.configure "development", ->
  js.liveUpdate css

app.get "/#{ config.uploadpath }", (req, res) ->
  res.render "upload.jade",
    main: {}
    networks: config.irc

app.get "/setup.json", (req, res) ->
  res.contentType "json"
  res.send
    networks: _.map(config.irc, (ob) -> ob.name)
    requiredVersion: 1


app.get new RegExp("^/i/([#{ urlshortener.alphabet }]+$)"), (req, res) ->
  url = req.params[0]
  jobid = urlshortener.decode url

  share = new ShareItem id: jobid, config: config
  share.load (err) ->
    if err
      winston.warn "Failed loading ShareItem #{ jobid }"
      res.end "OMG some error"
      return
    if not share.data.filename
      res.render "404.jade", status: 404, message: "No such image"
      return

    res.render "image.jade",
      share: share
      main:
        title: share.data.caption

    share.incrViews()




app.post "/#{ config.uploadpath }", (req, res) ->
  req.form.complete (err, fields, files) ->
    throw err if err
    res.contentType('json')

    for k, v of fields
      fields[k] = qs.unescape v

    fields.status = "starting"

    if not files?.picdata?.path
      winston.warn "Posted without pic", fields
      res.end JSON.stringify
        error: 1
        message: "Image is missing"
      return

    if not fields.deviceid
      winston.warn "Posted without deviceid", fields
      res.end JSON.stringify
        error: 1
        message: "Device id is missing"
      return

    if not fields.network
      winston.warn "Posted without network", fields
      res.end JSON.stringify
        error: 1
        message: "Network is missing"
      return


    fields.filename = path.basename files.picdata.path

    share = new ShareItem config: config
    share.load (err) ->
      return winston.error("failed to load share", err) if err
      winston.info "Adding resize-job for #{ share.id }"
      resizeJob = jobs.create "resizeimg",
        shareId: share.id
        title: "#{ fields.nick } is posting '#{ fields.caption }' to #{ fields.channel }@#{ fields.network }"
      share.set fields, (err) ->
        return winston.error("Failed to set fields to share", err) if err
        resizeJob.save (err) ->
          return winston.error("Failed to shave share", err) if err
          res.end JSON.stringify
            url: share.getUrl()



resizeCluster = cluster()
  .set("workers", 1)
  .use(cluster.debug())
  .start()



if resizeCluster.isMaster
  app.listen config.port
  kueui.listen 3000
else
  {resize} = require "./resize"
  jobs.process "resizeimg", (job, done) ->
    winston.info "Starting resize job #{ job.data.shareId }"
    share = new ShareItem id: job.data.shareId, config: config
    share.load (err) ->
      return done err if err
      share.set status: "resizing"
      resize share.getFsPath(), share.getSmallFsPath(), 640, (err) ->
        if err
          done err
        else
          winston.info "Adding irc-job for #{ job.data.shareId }"
          share.set status: "waiting to be posted to irc"
          ircJob = jobs.create "irc-#{ share.data.network.toLowerCase() }", job.data
          ircJob.save (err) ->
            if err
              done err
            else
              done()


