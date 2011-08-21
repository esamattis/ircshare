$ = jQuery
if not window.console?.log?
  window.console =
    log: ->

guidGenerator = ->
  S4 = ->
    (((1 + Math.random()) * 65536) | 0).toString(16).substring(1)

  (S4() + S4() + "-" + S4() + "-" + S4() + "-" + S4() + "-" + S4() + S4() + S4())

class EvenEmitter
  constructor: -> @_jq = jQuery {}

  on: (name, cb) ->
    @cbs ?= {}
    named = (@cbs[name] ?= [])
    named.push cb

  emit: (name, args...) ->
    if @cbs?[name]?
      for cb in @cbs[name]
        cb.apply this, args


class LightBox

  constructor: (settings) ->
    @el = settings.el
    @fade = settings.fade
    @content = @el.find(".box_content")

    @el.find(".close").click (e) =>
      e.preventDefault()
      @hide()
    @fade.click => @hide()

  info: (msg) ->
    @el.removeAttr "style"
    @content.html msg
    @show()

  error: (msg) ->
    @el.css "border-color", "red"
    @content.html msg
    @show()

  show: ->
    @el.show()
    @fade.show()

  hide: ->
    @el.hide()
    @fade.hide()


class Preview

  constructor: (settings) ->
    @el = settings.el
    @imgHolder = $ "#imgpreview", @el
    @imgCaption = $ "#imgcaption", @el

  if window.FileReader
    showImage: (file) ->
      reader = new FileReader()
      reader.onload = (e) =>
        console.log "LOAD"
        img = new Image
        img.src = e.target.result
        @imgHolder.html img
      reader.readAsDataURL file
  else
    showImage: ->

  setCaption: (str) ->
    if not $.trim str
      @imgCaption.html "&nbsp;"
    else
      @imgCaption.text str


hasModernUpload = window.XMLHttpRequest and window.FormData

class Upload extends EvenEmitter

  validChannel: /^[#!&]?[^#!& ]+$/

  constructor: (settings) ->
    super
    @el = settings.el

    @file = null
    @uploadButton = $("#upload", @el)
    if hasModernUpload
      @el.submit false
      @uploadButton.removeAttr("disabled")
      @uploadButton.click (e) =>
        e.preventDefault()
        @upload()

  upload: ->
    fd = new FormData
    xhr = new XMLHttpRequest
    $(xhr).bind "load", (e) =>
      res = JSON.parse e.currentTarget.response
      if res.error
        @emit "error", e, res
      else
        @emit "uploaded", e, res

    $(xhr).bind "error", (e) =>
      @emit "error", e
    $(xhr).bind "abort", (e) =>
      @emit "error", e
    $(xhr).bind "abort", (e) =>
      @emit "error", e

    if not @file
      @emit "invalid",  "Please select a file"
      return

    fd.append "picdata", @file

    ok = true
    @el.find("[name]").not("[type='file']").not("[type='submit']").each (i, e) =>
      e = $ e
      name = e.attr("name")
      value = e.val()

      if name is "channel" and not @validChannel.test value
        @emit "invalid", "Bad channel"
        ok = false
        return

      if not value
        ok = false
        @emit "invalid", "#{ name } is required!"
        return

      console.log name, value
      fd.append name, value

    if not ok
      return

    console.log "POST"
    xhr.open "POST", window.location.href
    xhr.send fd




# Load settings
$ ->
  if not window.localStorage.deviceId
    window.localStorage.deviceId = guidGenerator()
  $('[name="deviceid"]').attr "value", window.localStorage.deviceId
  $('[name="devicename"]').attr "value", window.navigator.appVersion
  $("form").dumbFormState()




$ ->
  preview = new Preview el: $("#preview")
  upload = new Upload el: $("form")
  lightbox = new LightBox
    el: $("#light")
    fade: $("#fade")

  upload.on "error", (e, res) ->
    console.log "error", e
    reason = res.message || ""
    lightbox.error "Upload failed. #{ reason }"

  upload.on "uploaded", (e, res) ->
    # res = JSON.parse e.currentTarget.response
    lightbox.info """Our workers has been summoned for your ircing duties.
    Find your image here <a href='#{ res.url }'>#{ res.url }</a>
    """

  upload.on "invalid", (msg) ->
    lightbox.error msg



  dragInfo = $("#dropinfo-bg,#dropinfo")
  fileInput = $("#picdata")
  fileInput.change (e) ->
    file = e.target.files[0]
    upload.file = file
    preview.showImage file

  captionTextArea = $("#caption")
  setCaption = ->
    preview.setCaption captionTextArea.val()
  setCaption()
  captionTextArea.edited setCaption


  $(document).bind "dragenter", (e) ->
    e.preventDefault()
    dragInfo.show()
    e.originalEvent.dataTransfer.dropEffect = 'copy'
  $(document).bind "dragover", (e) ->
    e.preventDefault()
    e.originalEvent.dataTransfer.dropEffect = 'copy'
  $(document).bind "dragleave", (e) ->
    e.preventDefault()
  $(document).bind "dragend", (e) ->
    e.preventDefault()
    dragInfo.hide()
  $(document).bind "drop", (e) ->
    e.preventDefault()
    dragInfo.hide()
    file = e.originalEvent.dataTransfer.files[0]
    upload.file = file
    preview.showImage file
  $(document).mouseout (e) ->
    dragInfo.hide()
  $(document).mouseenter (e) ->
    dragInfo.hide()
    console.log "mouse enter"




