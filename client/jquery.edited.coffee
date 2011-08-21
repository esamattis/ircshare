
jQuery.fn.edited = (callback) ->
    this.each ->
        that = $(this)

        active = false


        that.focusin ->
            active = true
        that.focusout ->
            active = false

        $(window).keyup ->
            callback(that) if active
