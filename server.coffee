fs = require "fs"
path = require "path"
qs = require "querystring"

express = require "express"
redis = require "redis"
form = require('connect-form')
stylus = require "stylus"
nib = require "nib"

_  = require 'underscore' 
_.mixin require 'underscore.string' 

addCodeSharingTo = require("express-share").addCodeSharingTo

urlsortener = require "./urlsortener"

kue = require "kue"
config = JSON.parse fs.readFileSync "./config.json"


kue.redis.createClient = ->
  client = redis.createClient(config.redis.port, config.redis.host)
  if config.redis.pass?
    client.auth config.redis.pass
  client

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
      console.log path
      stylus(str).set("filename", path).use(nib())

  addCodeSharingTo app


app.shareFs __dirname + "/client/vendor/jquery.js"
app.shareFs __dirname + "/client/vendor/underscore.js"
app.shareFs __dirname + "/client/vendor/backbone.js"
app.shareFs __dirname + "/client/vendor/dumbformstate.js"
app.shareFs __dirname + "/client/main.coffee"

app.get "/#{ config.uploadpath }", (req, res) ->
  res.render "upload.jade"

app.get new RegExp("^/([#{ urlsortener.alphabet }]+$)"), (req, res) ->
  url = req.params[0]
  jobid = urlsortener.decode url

  kue.Job.get jobid, (err, job) ->
    throw err if err
    res.render "image.jade", _.extend({}, job.data, config)




app.post "/#{ config.uploadpath }", (req, res) ->

  req.form.complete (err, fields, files) ->
    if err then throw err

    for k, v of fields
      fields[k] = qs.unescape v

    fields.img = path.basename files.picdata.path
    fields.title = "#{ fields.nick } is posting '#{ fields.caption }' to #{ fields.channel }@#{ fields.network }"

    console.log fields.title, "ID", fields.deviceid
    console.log "NAME", fields.devicename

    job = jobs.create "irc-#{ fields.network.toLowerCase() }", fields
    job.save()

    res.end(fields.url)


app.listen config.port
kueui.listen 3000
