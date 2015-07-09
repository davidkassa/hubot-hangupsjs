util = require 'util'
validUrl = require 'valid-url'
try
  {Adapter, TextMessage, EnterMessage, LeaveMessage, TopicMessage, User} = require 'hubot'
catch
  prequire = require 'parent-require' 
  {Adapter, TextMessage, EnterMessage, LeaveMessage, TopicMessage, User} = prequire 'hubot'
  
HangupsClient = require 'hangupsjs'
Promise = require "bluebird"
 
  # An adapter is a specific interface to a chat source for robots.
class HangupsJS extends Adapter

  # robot - A Robot instance.
  constructor: (@robot) ->

  # Public: Raw method for invoking the bot to run. Extend this.
  #
  # Returns nothing.
  run: ->
    @robot.logger.debug 'Run'
    
    @client = new HangupsClient()
    
    @client.loglevel @robot.logger.level
    
    @client.on 'connecting', @.connecting
    @client.on 'connected', @.connected
    @client.on 'connect_failed', @.connect_failed

    @client.on 'chat_message', @.chat_message
    @client.on 'membership_change', @.membership_change
    @client.on 'conversation_rename', @.conversation_rename
    
    @creds = -> auth: () -> process.env.HUBOT_GOOGLE_AUTH_TOKEN || HangupsClient.authStdin()
    @client.connect @creds

  connecting: =>
    @robot.logger.info 'Client Connecting'

  connected: =>
    @robot.logger.info 'Client Connected'
    @client.setpresence(true).then( (res) => @robot.logger.debug res)
    
    @client.getselfinfo().then( (self) =>
      @robot.logger.debug self
      @self = self
      @emit "connected" # Tell Hubot we're connected so it can load scripts
    ).catch (error) =>
      @robot.logger.error error

    
  connect_failed: (err) =>
    @robot.logger.info "Client Connect Failed #{err}"
    Promise.delay(3000).then(() => @client.connect @creds)

  chat_message: (msg) =>
    @robot.logger.debug 'chat_message'
    @robot.logger.debug msg

    return if msg.sender_id.chat_id == @self.self_entity.id.chat_id
    return if not msg.chat_message.message_content.segment #currently don't support attachments

    Promise.join @getSender(msg), msg, (user, msg) =>
      msgSegment = msg.chat_message.message_content.segment
      @robot.logger.debug msgSegment

      #msgAttachment = msg.chat_message.message_content.attachment
      #@robot.logger.debug msgAttachment
      #@robot.logger.debug msgAttachment[0].embed_item.type_
      #@robot.logger.debug msgAttachment[0].embed_item.data

      text = msgSegment.map( (m) -> m.text)
        .filter((i) -> i)
        .join('')

      @robot.logger.debug "Chat message: #{text}"
    
      user.room = msg.conversation_id.id
      @receive new TextMessage(user, text, msg.event_id)
      @updateWatermark msg
    .catch (error) =>
      @robot.logger.error error

  membership_change: (msg) =>
    @robot.logger.debug 'membership_change'
    @robot.logger.info msg
    
    for participant in msg.membership_change.participant_ids
      Promise.join @getUser(participant.chat_id), (user) =>
        if msg.membership_change.type == "JOIN" then m = new EnterMessage(user, null, msg.event_id)
        else if msg.membership_change.type == "LEAVE" then m = new LeaveMessage(user, null, msg.event_id)

        user.room = msg.conversation_id.id
        @receive m
        @updateWatermark msg
      .catch (error) =>
        @robot.logger.error error

  conversation_rename: (msg) =>
    @robot.logger.debug 'conversation_rename'
    @robot.logger.info msg

    Promise.join @getSender(msg), msg, (user, msg) =>
      newName = msg.conversation_rename.new_name
      @robot.logger.debug "Conversation Rename: #{newName}"
      user.room = msg.conversation_id.id
      @receive new TopicMessage(user, newName, msg.event_id)
      @updateWatermark msg
    .catch (error) =>
      @robot.logger.error error


  getSender: (msg) =>
    @getUser(msg.sender_id.chat_id)

  getUser: (userId) =>
    @client.getentitybyid([userId]).then (res) => 
     for entity in res.entities
       @robot.logger.debug entity.properties
       @robot.logger.debug entity.properties.emails
      senderProps = res.entities[0].properties
      new User(userId, {first_name: senderProps.first_name, name: senderProps.display_name
      display_name: senderProps.display_name, photo_url: senderProps.photo_url, emails: senderProps.emails })

  updateWatermark: (msg) =>
    @client.updatewatermark(msg.conversation_id.id, msg.timestamp / 1000)#.then( (res) => @robot.logger.debug res)
    @client.setfocus(msg.conversation_id.id)#.then( (res) => @robot.logger.debug res)

  # Public: Raw method for sending data back to the chat source. Extend this.
  #
  # envelope - A Object with message, room and user details.
  # strings  - One or more Strings for each message to send.
  #
  # Returns nothing.
  send: (envelope, strings...) ->
    @robot.logger.debug 'Send'
    builder = new HangupsClient.MessageBuilder()
    for msg in strings
      if validUrl.isUri(msg)
        builder.link(msg,msg)
      else
        builder.text msg

    @client.sendchatmessage envelope.room, builder.toSegments()
    
  # Public: Raw method for sending emote data back to the chat source.
  # Defaults as an alias for send
  #
  # envelope - A Object with message, room and user details.
  # strings  - One or more Strings for each message to send.
  #
  # Returns nothing.
  emote: (envelope, strings...) ->
    @robot.logger.debug 'Emote'
    @send envelope, strings...

  # Public: Raw method for building a reply and sending it back to the chat
  # source. Extend this.
  #
  # envelope - A Object with message, room and user details.
  # strings  - One or more Strings for each reply to send.
  #
  # Returns nothing.
  reply: (envelope, strings...) ->
    @robot.logger.debug 'Reply'
    @send envelope, strings...

  # Public: Raw method for setting a topic on the chat source. Extend this.
  #
  # envelope - A Object with message, room and user details.
  # strings  - One more more Strings to set as the topic.
  #
  # Returns nothing.
  topic: (envelope, strings...) ->
    @robot.logger.debug 'Topic'
    @client.renameconversation envelope.room, strings.join "\n"

  # Public: Raw method for playing a sound in the chat source. Extend this.
  #
  # envelope - A Object with message, room and user details.
  # strings  - One or more strings for each play message to send.
  #
  # Returns nothing
  play: (envelope, strings...) ->
    @robot.logger.debug 'Play'

  # Public: Raw method for shutting the bot down. Extend this.
  #
  # Returns nothing.
  close: ->
    @robot.logger.debug 'Close'
    @client.setpresence(false).then( (res) => @robot.logger.debug res)
    @client.disconnect().then( (res) => @robot.logger.debug res)

  # Public: Dispatch a received message to the robot.
  #
  # Returns nothing.
  receive: (message) ->
    @robot.logger.debug 'Receive'
    @robot.logger.debug message
    @robot.receive message

module.exports = HangupsJS