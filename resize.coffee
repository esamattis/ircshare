
fs = require "fs"
Canvas = require "canvas"
Image = Canvas.Image


exports.resize = (inputPath, outputPath, maxWidth, cb) ->
  img = new Image
  img.onerror = (err) ->
    cb? err

  img.onload = ->
    if img.width < maxWidth and img.height < maxWidth
      height = img.height
      width = img.width
    else if img.width > img.height
      scale = maxWidth / img.width
      width = maxWidth
      height = img.height * scale
    else
      scale = maxWidth / img.height
      height = maxWidth
      width = img.width * scale

    canvas = new Canvas(width, height)
    ctx = canvas.getContext "2d"
    ctx.drawImage(img, 0, 0, width, height)
    canvas.toBuffer (err, buf) ->
      fs.writeFile outputPath, buf, (err) ->
        cb?(err)

  console.log "resing imgae in", inputPath
  img.src = inputPath

if require.main is module
  # exports.resize "/home/epeli/projects/ircshare/server/public/img/717074ae25c8a7e0040d8ecbb5991a06.jpg", "resized.png", 100, ->
  #   console.log "done"
  exports.resize "/home/epeli/Pictures/ensiodvd_coveri_mini.jpg", "resized.png", 100, ->
    console.log "done"
