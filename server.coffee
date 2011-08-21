fs = require "fs"
path = require "path"
qs = require "querystring"

express = require "express"
cluster = require "cluster"
redis = require "redis"
form = require('connect-form')
stylus = require "stylus"
nib = require "nib"
kue = require "kue"
_  = require 'underscore'
_.mixin require 'underscore.string'

addCodeSharingTo = require("express-share").addCodeSharingTo

urlsortener = require "./urlsortener"
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

  addCodeSharingTo app


app.shareFs __dirname + "/client/vendor/jquery.js"
app.shareFs __dirname + "/client/vendor/jquery.validate.js"
app.shareFs __dirname + "/client/vendor/underscore.js"
app.shareFs __dirname + "/client/vendor/backbone.js"
app.shareFs __dirname + "/client/vendor/dumbformstate.js"
app.shareFs __dirname + "/client/jquery.edited.coffee"
app.shareFs __dirname + "/client/main.coffee"

app.get "/#{ config.uploadpath }", (req, res) ->
  res.render "upload.jade",
    main: {}


app.get new RegExp("^/([#{ urlsortener.alphabet }]+$)"), (req, res) ->
  url = req.params[0]
  jobid = urlsortener.decode url

  share = new ShareItem id: jobid, config: config
  share.load (err) ->
    if err
      console.log err
      res.end "OMG some error"
      return
    if not share.data.filename
      res.render "404.jade", status: 404, message: "No such image"
      return

    console.log "res", share.data
    res.render "image.jade",
      share: share
      main:
        title: share.data.caption

    share.incrViews()




app.post "/#{ config.uploadpath }", (req, res) ->
  req.form.complete (err, fields, files) ->
    if err then throw err
    res.contentType('json')

    for k, v of fields
      fields[k] = qs.unescape v

    fields.status = "starting"


    if not files?.picdata?.path
      res.end JSON.stringify
        error: 1
        message: "Image is missing"
      return

    if not fields.deviceid
      res.end JSON.stringify
        error: 1
        message: "Device id is missing"
      return

    if not fields.network
      res.end JSON.stringify
        error: 1
        message: "Network is missing"
      return

    fields.filename = path.basename files.picdata.path
    console.log "filename IS", fields.filename

    share = new ShareItem config: config
    share.load (err) ->
      throw err if err
      resizeJob = jobs.create "resizeimg",
        shareId: share.id
        title: "#{ fields.nick } is posting '#{ fields.caption }' to #{ fields.channel }@#{ fields.network }"
      share.set fields, (err) ->
        throw err if err
        resizeJob.save (err) ->
          throw err if err
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
    share = new ShareItem id: job.data.shareId, config: config
    share.load (err) ->
      return done err if err
      share.set status: "resizing"
      resize share.getFsPath(), share.getSmallFsPath(), 640, (err) ->
        if err
          done err
        else
          share.set status: "waiting to be posted to irc"
          ircJob = jobs.create "irc-#{ share.data.network.toLowerCase() }", job.data
          ircJob.save (err) ->
            if err
              done err
            else
              done()


