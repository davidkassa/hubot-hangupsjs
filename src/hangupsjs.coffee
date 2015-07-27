util = require 'util'
validUrl = require 'valid-url'
isImage = require 'is-image'
normalizeNewline = require 'normalize-newline'
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
    
    #TODO: 7 = DEBUG, 6 = INFO, ... 4 = WARNING, 3 = ERROR
    #@client.loglevel @robot.logger.level
    
    @initUserList = []
    @robot.brain.on 'loaded', @.brainLoaded
    
    @client.on 'connecting', @.connecting
    @client.on 'connected', @.connected
    @client.on 'connect_failed', @.connect_failed

    @client.on 'chat_message', @.chat_message
    @client.on 'membership_change', @.membership_change
    @client.on 'conversation_rename', @.conversation_rename
    
    @creds = -> auth: () -> process.env.HUBOT_GOOGLE_AUTH_TOKEN || HangupsClient.authStdin()
    @client.connect @creds

  brainLoaded: =>
    @robot.logger.info 'Brain Loaded...updating user list'
    @updateUsers @initUserList

  connecting: =>
    @robot.logger.info 'Client Connecting'

  connected: =>
    @robot.logger.info 'Client Connected'
    @client.setpresence(true)
    @client.getselfinfo().then( (self) =>
      @robot.logger.debug self
      @self = self
    ).then( () => 
      @emit "connected" # Tell Hubot we're connected so it can load scripts
    ).then( () =>
      #reach into init object for all conversations
      chatIds = []
      for cs in @client.init.conv_states
        chatIds = chatIds.concat(cs.conversation.current_participant.map((o) -> o.chat_id))
      chatIds = chatIds.filter( (val, index, self) -> index == self.indexOf(val) )

      @getUsers(chatIds).then( (users) => 
        @initUserList = users #stash users for delayed brain load
        @updateUsers(users) #update users for synchronous brain
      )
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

    Promise.join @getSender(msg), msg, (users, msg) =>
      user = users[0]
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
      #TODO: batch participants
      Promise.join @getUsers(participant.chat_id), (userList) =>
        user = userList[0]
        if msg.membership_change.type == "JOIN"
          @updateUsers userList
          user.room = msg.conversation_id.id # try to keep room out of brain
          m = new EnterMessage(user, null, msg.event_id)
        else if msg.membership_change.type == "LEAVE"
          user.room = msg.conversation_id.id
          m = new LeaveMessage(user, null, msg.event_id)

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
    @getUsers(msg.sender_id.chat_id)

  getUsers: (userIds) =>
    @robot.logger.debug 'getUsers'

    @client.getentitybyid([].concat(userIds)).then (res) => 
      for entity in res.entities
        @robot.logger.debug entity.id.chat_id
        @robot.logger.debug entity.properties
        @robot.logger.debug entity.properties.emails
        userProps = entity.properties
        new User(entity.id.chat_id, {first_name: userProps.first_name, name: userProps.display_name
        display_name: userProps.display_name, photo_url: userProps.photo_url, emails: userProps.emails })

  updateUsers: (users) =>
    @robot.logger.debug 'updateUsers'

    for user in [].concat(users)
      if user.id of @robot.brain.data.users
        for key, value of @robot.brain.data.users[user.id]
          unless key of user
            user[key] = value
      delete @robot.brain.data.users[user.id]
      @robot.brain.userForId user.id, user

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
      if isImage(msg) # todo, handle images better
        builder.link(msg,msg)
      else if validUrl.isUri(msg)
        builder.link(msg,msg)
      else
        msgArray = normalizeNewline(msg).split("\n")
        for m, i in msgArray    
          builder.text m
          if i != msgArray.length - 1 then builder.linebreak()

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