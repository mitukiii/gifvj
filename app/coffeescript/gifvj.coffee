###
# GifVJ Class
###
class GifVJ
  constructor: (canvas, urls, handler) ->
    @canvas = canvas
    @context = @canvas.getContext '2d'
    @urls = urls
    @handler = handler || {}
    @parsers = []
    @datas = []
    @errors = []
    @parserHandler =
      onParseProgress: $.proxy(@onParseProgress, this)
      onParseComplete: $.proxy(@onParseComplete, this)
      onParseError: $.proxy(@onParseError, this)
    @load()

  load: ->
    self = this
    for url in @urls
      $.ajax
        url: url
        beforeSend: (req) ->
          req.overrideMimeType 'text/plain; charset=x-user-defined'
        complete: (req) ->
          data = req.responseText
          parser = new GifVJ.Parser data, null, self.parserHandler
          self.parsers.push parser

  initPlayerIfCompleted: ->
    return unless @datas.length + @errors.length == @parsers.length
    @slots = [
      {offset: 0,  index: 0}
      {offset: 9,  index: 0}
      {offset: 18, index: 0}
      {offset: 27, index: 0}
      {offset: 36, index: 0}
    ]
    @slot = @slots[0]
    @player = new GifVJ.Player(@canvas, @datas[@slot.offset + @slot.index])
    @handler.onComplete && @handler.onComplete this

  onParseProgress: (parser) ->
    return unless parser.frames.length > 0
    frame = parser.frames[parser.frames.length - 1]
    @canvas.width = parser.header.width
    @canvas.height = parser.header.height
    @context.putImageData(frame, 0, 0)

  onParseComplete: (parser) ->
    @datas.push
      frames: parser.frames
      width: parser.header.width
      height: parser.header.height
    percent = Math.round(@datas.length / @urls.length * 100)
    @handler.onProgress && @handler.onProgress this, percent
    @initPlayerIfCompleted()

  onParseError: (parser, error) ->
    @errors.push error
    @handler.onError && @handler.onError this, error
    @initPlayerIfCompleted()

  onKeyDown: (e) ->
    return unless @player
    return if $(e.target).isInput()
    return if e.hasModifierKey()
    e.preventDefault()
    switch e.which
      when 13 # Enter
        @player.toggle()
      when 39, 74 # j / →
        @player.nextFrame()
      when 37, 75 # k / ←
        @player.prevFrame()
      when 82 # r
        @player.setReverse !@player.reverse
      when 32 # Space
        if @beforeTapTime
          diffTime = new Date - @beforeTapTime
          if diffTime <= 2000
            @player.setDelay diffTime / 8
        @beforeTapTime = new Date
      when 49, 50, 51, 52, 53, 54, 55, 56, 57, 89, 85, 73, 79, 80 # 1-9, y, u, i, o, p
        keycode = e.which
        if keycode >= 49 && keycode <= 57
          @slot.index = keycode - 49
        else
          switch keycode
            when 89 then @slot = @slots[0]
            when 85 then @slot = @slots[1]
            when 73 then @slot = @slots[2]
            when 79 then @slot = @slots[3]
            when 80 then @slot = @slots[4]
        index = @slot.offset + @slot.index
        while index >= 0
          data = @datas[index]
          if data
            @player.setData data
            return
          index = index - @datas.length

  start: ->
    return unless @player
    @player.play()

class GifVJ.Parser
  constructor: (data, canvas, handler) ->
    @stream = new Stream(data)
    @canvas = canvas || document.createElement 'canvas'
    @handler = handler || {}
    @frames = []
    @parse()

  parse: ->
    try
      parseGIF @stream,
        hdr: $.proxy(@onParseHeader, this)
        gce: $.proxy(@onParseGraphicControlExtension, this)
        img: $.proxy(@onParseImage, this)
        eof: $.proxy(@onEndOfFile, this)
    catch error
      if @handler.onParseError
        @handler.onParseError this, error
      else
        throw error

  pushFrame: ->
    if @context
      @frames.push @context.getImageData(0, 0, @header.width, @header.height)
      @context = null

  onParseHeader: (header) ->
    @header = header
    @canvas.width = @header.width
    @canvas.height = @header.height

  onParseGraphicControlExtension: (gce) ->
    @pushFrame()
    @transparency = if gce.transparencyGiven then gce.transparencyIndex else null
    @disposal_method = gce.disposalMethod

  onParseImage: (image) ->
    unless @context
      @context = @canvas.getContext '2d'
    color_table = if image.lctFlag then image.lct else @header.gct
    data = @context.getImageData(image.leftPos, image.topPos, image.width, image.height)
    for pixel, index in image.pixels
      if @transparency != pixel
        data.data[index * 4 + 0] = color_table[pixel][0]
        data.data[index * 4 + 1] = color_table[pixel][1]
        data.data[index * 4 + 2] = color_table[pixel][2]
        data.data[index * 4 + 3] = 255
      else if @disposal_method == 2 || @disposal_method == 3
        data.data[index * 4 + 3] = 0
    @context.putImageData(data, image.leftPos, image.topPos)
    @handler.onParseProgress && @handler.onParseProgress this

  onEndOfFile: ->
    @pushFrame()
    if @frames.length > 1
      @handler.onParseComplete && @handler.onParseComplete this
    else
      @handler.onParseError && @handler.onParseError this, new Error 'Not a animation GIF file.'

class GifVJ.Player
  constructor: (canvas, data)->
    @canvas = canvas
    @context = canvas.getContext('2d')
    @setData data
    @playing = false
    @reverse = false
    @delay = 100

  setData: (data) ->
    @data = data
    @frames = @data.frames
    @index = 0
    @canvas.width = @data.width
    @canvas.height = @data.height
    setTimeout($.proxy(@setFrame, this), 0)

  setFrame: ->
    frame = @frames[@index]
    return unless frame
    @context.putImageData(frame, 0, 0)

  stepFrame: ->
    return unless @playing
    @setFrame()
    if @reverse
      @index -= 1
      if @index < 0
        @index = @frames.length - 1
    else
      @index += 1
      if @index >= @frames.length
        @index = 0
    setTimeout $.proxy(@stepFrame, this), @delay

  play: ->
    @playing = true
    @stepFrame()

  stop: ->
    @playing = false

  toggle: ->
    if @playing
      @stop()
    else
      @play()

  nextFrame: ->
    return if @playing
    @index += 1
    if @index >= @frames.length
      @index = 0
    @setFrame()

  prevFrame: ->
    return if @playing
    @index -= 1
    if @index < 0
      @index = @frames.length - 1
    @setFrame()

  setReverse: (reverse) ->
    @reverse = reverse

  setDelay: (delay) ->
    @delay = delay
