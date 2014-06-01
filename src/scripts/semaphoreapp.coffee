# Description
#   Integration with Semaphore (semaphoreapp.com)
#
# Dependencies:
#   None
#
# Configuration:
#   HUBOT_SEMAPHOREAPP_TRIGGER
#     Comma-separated list of additional keywords that will trigger
#     this script (e.g., "build")
#
#   HUBOT_SEMAPHOREAPP_AUTH_TOKEN
#     Your authentication token for Semaphore API
#
#   HUBOT_SEMAPHOREAPP_NOTIFY_RULES
#     Comma-separated list of rules. A rule consists of a room and an
#     *optional* regular expression separated with a colon (i.e., ':').
#     Right-hand side of a rule is to match branch names, so you can do things
#     like notifying "The Serious Room" for master branch, and discard all other
#     notifications. If you omit right-hand side of a rule then room will
#     be notified for any branch.
#
#     Note: If you're using the built-in Campfire adapter then a "room" would be
#           one of the Campfire room ids configured in HUBOT_CAMPFIRE_ROOMS.
#
#     Examples:
#
#       "The Internal Room"
#         =>  Notifications of any branch or project go to "The Internal Room".
#
#       "The Serious Room::master"
#         =>  Notifications of any project's master branch go to
#             "The Serious Room", notifications of other branches will be
#             discarded.
#
#       "The Developers Room:Blog:master"
#         =>  Notifications of the project "Blog"'s master branch go to
#             "The Serious Room", notifications of other branches will be
#             discarded.
#
#       "The Serious Room:Blog:master,The Internal Room:(?!Blog):"
#         =>  Notifications of the project "Blog"'s master branch go to
#             "The Serious Room", notifications of any project's branches,
#             except "Blog" go to "The Internal Room".
#
#       "The Developers Room::.*(test|experiment).*"
#         =>  Notifications of branches that contain "test" or "experiment"
#             from any project go to "The Developers Room", notifications of
#             other branches will be discarded.
#
# Commands:
#   hubot semaphore status [<project> [<branch>]] - Reports build status for projects' branches
#
# URLs:
#   POST /hubot/semaphoreapp
#     First, read http://docs.semaphoreapp.com/webhooks, then your URL to
#     receive the payload would be "<HUBOT_URL>:<PORT>/hubot/semaphoreapp"
#     or if you deployed Hubot onto Heroku: "<HEROKU_URL>/hubot/semaphoreapp".
#
# Author:
#   exalted, uxp
#

@adapter = undefined

module.exports = (robot) ->
  @adapter = robot.adapter.constructor.name

  if process.env.HUBOT_SEMAPHOREAPP_TRIGGER
    trigger = process.env.HUBOT_SEMAPHOREAPP_TRIGGER.split(',').join('|')

  robot.respond new RegExp("(?:semaphoreapp|#{trigger})\\s+build(?:\\s+(\\S+)(?:\\s+(\\S+))?)?\\s*$", "i"), (msg) ->
    semaphoreapp = new SemaphoreApp msg

    # Read parameters
    projectName = msg.match[1]
    branchName = msg.match[2]

    projectHash = robot.brain.get("SemaphoreApp:#{projectName}")
    branchId = robot.brain.get("SemaphoreApp:#{projectName}:#{branchName}")

    unless projectHash?
      msg.reply "Woah, I totally don't know about that repo, but let me see if it exists..."
      semaphoreapp.getListOfAllProjects (projects) ->
        unless projects.length > 0
          msg.reply "Something is wrong. I literally can't see a thing. Am I blind?"
          return

        for p in projects
          if p.name is projectName
            project = p
            break

        unless project?
          msg.reply "Yeah, I don't know anything about \"#{projectName}\". I don't think it exists."
          return

        projectHash = project.hash_id
        robot.brain.set("SemaphoreApp:#{projectName}", projectHash)

    unless branchId?
      msg.reply "Are you sure that branch exists? Let me check on it first..."
      semaphoreapp.getListOfBranchesForProject projectHash, (branches) ->
        unless branchName
          branchName = 'master'

        for b in branches
          if b.name is branchName
            branch = b
            break

        unless branch?
          msg.reply "Uh, I don't seem to know about the branch \"#{branchName}\"."
          return

        branchId = branch.id
        robot.brain.set("SemaphoreApp:#{projectName}:#{branchName}", branchId)

    semaphoreapp.rebuildLastRevisionForBranch projectHash, branchId, (rebuild) ->
      console.log(rebuild)
      if rebuild.html_url
        msg.reply "Rebuilding branch '#{rebuild.branch_name}' of '#{rebuild.project_name}'\n(#{rebuild.html_url})"


  robot.respond new RegExp("(?:semaphoreapp|#{trigger})\\s+status(?:\\s+(\\S+)(?:\\s+(\\S+))?)?\\s*$", "i"), (msg) ->
    semaphoreapp = new SemaphoreApp msg

    # Read parameters
    projectName = msg.match[1]
    branchName = msg.match[2]

    semaphoreapp.getListOfAllProjects (projects) ->
      unless projects.length > 0
        msg.reply "I don't know anything really. Sorry. #{embelishEmoji 'cry'}"
        return

      # unless projectName
      #
      #   # TODO recall project name for current user
      unless branchName
        branchName = "master"

      unless projectName
        if projects.length > 1
          names = (x.name for x in projects)
          msg.reply "I want to do so many things, trying to decide, but... #{embelishEmoji 'sweat'}\nHow about #{tellEitherOneOfThese names} instead?"

          return
        else
          project = projects[0]

      unless project?
        for x in projects
          if x.name is projectName
            project = x
            break

      unless project?
        if projects.length > 1
          names = (x.name for x in projects)
          butTellAlsoThis = "How about #{tellEitherOneOfThese names} instead?"
        else
          butTellAlsoThis = "Do you mean \"#{projects[0].name}\" perhaps? #{embelishEmoji 'wink'}"

        msg.reply "I don't know anything about \"#{projectName}\" project. Sorry. #{embelishEmoji 'cry'}\n#{butTellAlsoThis}"
        return

      # TODO remember last asked project name for current user
      unless project.branches.length > 0
        msg.reply "I can't find any branches for the project \"#{projectName}\". Sorry. #{embelishEmoji 'cry'}"
        return

      for x in project.branches
        if x.branch_name is branchName
          branch = x
          break

      unless branch?
        if project.branches.length > 1
          names = (x.branch_name for x in project.branches)
          butTellAlsoThis = "How about #{tellEitherOneOfThese names} instead?"
        else
          butTellAlsoThis = "Do you mean \"#{project.branches[0].branch_name}\" perhaps? #{embelishEmoji 'wink'}"

        msg.reply "I don't know anything about a branch named \"#{branchName}\" branch. Sorry. #{embelishEmoji 'cry'}\n#{butTellAlsoThis}"
        return

      msg.reply statusMessage(branch)

  robot.router.post "/hubot/semaphoreapp", (req, res) ->
    unless process.env.HUBOT_SEMAPHOREAPP_NOTIFY_RULES
      message = "semaphoreapp hook warning: HUBOT_SEMAPHOREAPP_NOTIFY_RULES is empty."
      res.send(500, { error: message })
      console.log message
      return

    try
      payload = req.body
    catch error
      message = "semaphoreapp hook error: #{error}. Payload: #{req.body}"
      res.send(400, message)
      console.log message
      return

    res.send()

    rules = process.env.HUBOT_SEMAPHOREAPP_NOTIFY_RULES.split(',')
    for rule in (x.split(':') for x in rules)
      room = rule[0]
      project = rule[1]
      branch = rule[2]

      try
        projectRegExp = new RegExp("^#{project}$" if project)
      catch error
        console.log "semaphoreapp error: #{error}."
        return

      try
        branchRegExp = new RegExp("^#{branch}$" if branch)
      catch error
        console.log "semaphoreapp error: #{error}."
        return

      if projectRegExp.test(payload.project_name) && branchRegExp.test(payload.branch_name)
        robot.messageRoom room, statusMessage(robot, payload)

tellEitherOneOfThese = (things) ->
  "\"#{things[...-1].join('\", \"')}\" or \"#{things[-1..]}\""

statusEmoji = (status) ->
  if @adapter
    switch @adapter
      when 'Shell'
        switch status
          when "passed" then "☑"
          when "failed" then "☒"
          when "pending" then "☐"
      when 'Campfire'
        switch status
          when "passed" then ":white_check_mark:"
          when "failed" then ":x:"
          when "pending" then ":warning:"
      when 'HipChat'
        switch status
          when "passed" then "(successful)"
          when "failed" then "(failed)"
          when "pending" then "(shrug)"


embelishEmoji = (status) ->
  if @adapter
    switch @adapter
      when 'Shell'
        switch status
          when "cry" then ":'("
          when "confused" then ":#"
          when "wink" then ";)"
          when "sweat" then ":("
      when 'Campfire'
        switch status
          when "cry" then ":cry:"
          when "confused" then ":confused:"
          when "wink" then ":wink:"
          when "sweat" then ":sweat:"
      when 'HipChat'
        switch status
          when "cry" then ":'("
          when "confused" then ":#"
          when "wink" then ";)"
          when "sweat" then "(oops)"



statusMessage = (branch) ->
  refSpec = "#{branch.project_name}/#{branch.branch_name}"
  result = "#{branch.result[0].toUpperCase() + branch.result[1..-1].toLowerCase()}"
  message = if branch.commit then " \"#{branch.commit.message.split(/\n/)[0]}\"" else ""
  authorName = if branch.commit then " - #{branch.commit.author_name}" else ""
  buildURL = "#{branch.build_url}"
  "#{statusEmoji branch.result} [#{refSpec}] #{result}:#{message}#{authorName} (#{buildURL})"

class SemaphoreApp
  constructor: (msg) ->
    @msg = msg

  getListOfAllProjects: (callback) ->
    unless process.env.HUBOT_SEMAPHOREAPP_AUTH_TOKEN
      @msg.reply "I am not allowed to access Semaphore APIs, sorry. #{embelishEmoji 'cry'}"
      return

    msg = @msg
    @msg.robot.http("https://semaphoreapp.com/api/v1/projects")
      .query(auth_token: "#{process.env.HUBOT_SEMAPHOREAPP_AUTH_TOKEN}")
      .get() (err, res, body) ->
        try
          json = JSON.parse body
        catch error
          console.log "semaphoreapp error: #{error}."
          msg.reply "Semaphore is talking gibberish right now. Try again later?! :confused:"
          return

        callback json

  getListOfBranchesForProject: (projectHash, callback) ->
    unless process.env.HUBOT_SEMAPHOREAPP_AUTH_TOKEN
      @msg.reply "I am not allowed to access Semaphore APIs, sorry. #{embelishEmoji 'cry'}"
      return

    unless projectHash && projectHash.length == 40
      @msg.reply "I'm sorry, Dave. I'm afraid I can't do that.\nI think you know what the problem is just as well as I do."
      return

    msg = @msg
    @msg.robot.http("https://semaphoreapp.com/api/v1/projects/#{projectHash}/branches") # ?auth_token=#{process.env.HUBOT_SEMAPHOREAPP_AUTH_TOKEN}")
      .query(auth_token: "#{process.env.HUBOT_SEMAPHOREAPP_AUTH_TOKEN}")
      .get() (err, res, body) ->
        try
          json = JSON.parse body
        catch error
          console.log "semaphoreapp error: #{error}."
          msg.reply "Semaphore is talking gibberish right now. Try again later?! #{embelishEmoji 'confused'}"
          return

        callback json

  rebuildLastRevisionForBranch: (project, branch, callback) ->
    unless process.env.HUBOT_SEMAPHOREAPP_AUTH_TOKEN
      @msg.reply "I am not allowed to access Semaphore APIs, sorry. #{embelishEmoji 'cry'}"
      return

    unless project.length == 40
      @msg.reply "I'm sorry, Dave. I'm afraid I can't do that.\nI think you know what the problem is just as well as I do."
      return

    msg = @msg
    data = JSON.stringify({auth_token: "#{process.env.HUBOT_SEMAPHOREAPP_AUTH_TOKEN}"})
    @msg.robot.http("https://semaphoreapp.com/api/v1/projects/#{project}/#{branch}/build")
      .header('Content-Type', 'application/json')
      .post(data) (err, res, body) ->
        try
          json = JSON.parse body
        catch error
          console.log "semaphoreapp error: #{error}."
          msg.reply "Semaphore is talking gibberish right now. Try again later?! #{embelishEmoji 'confused'}"
          return

        callback json

