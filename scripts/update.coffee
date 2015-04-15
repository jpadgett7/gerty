# Description:
#   Posts updates to status.megaminerai.com
#
# Commands:
#   hubot update <component> to <status>; <title>: <message> - Post a new status update
#
# Configuration:
#   HUBOT_STATUS_REPO_NAME - The name of the status repository to use.
#   HUBOT_STATUS_REPO_OWNER - The name of the repository's owner.
#   HUBOT_STATUS_UPDATE_ROLE - The `hubot-auth` role required to submit updates.
#       Defaults to 'updater'.
#   HUBOT_STATUS_GITHUB_TOKEN - GitHub Token with `repo` scope for a user
#       who is authorized to write to the given repo
#

_ = require "underscore"
GitHubAPI = require("github")
moment = require "moment"
slug = require "slug"
yaml = require "js-yaml"


# Configuration Options
config =
    layout: "update"
    categories: _ ["arena", "food", "gameserver", "git", "visualizer", "webserver"]
    tags: _ ["OK", "Warning", "Down"]
    cred:
        token: process.env.HUBOT_STATUS_GITHUB_TOKEN
    repo:
        name: process.env.HUBOT_STATUS_REPO_NAME
        owner: process.env.HUBOT_STATUS_REPO_OWNER
    update_role: process.env.HUBOT_STATUS_UPDATE_ROLE or "updater"


# API Helper
github = new GitHubAPI
    version: "3.0.0"
    debug: false
    protocol: "https"
    timeout: 5000
    headers:
        "user-agent": "SIG-Game-Hubot-Gerty"

# Authenticate if possible
if config.cred.token?
    github.authenticate
        type: "oauth"
        token: config.cred.token


class UpdateError
    ###
    An Error class for throwing
    ###
    constructor: (@message) ->


joinString = (char, _lst) ->
    ###
    Joins a list of strings together, separated by 'char's
    ###
    maybeJoin = (x, y) -> if x == "" then y else x + char + y
    _lst.reduce maybeJoin, ""


validateUpdate = (update) ->
    ###
    Validates an update object to ensure it has necessary fields
    ###

    # Ensure we're using a real category
    if not config.categories.contains(update.category)
        choices = joinString ", ", config.categories
        throw new UpdateError("Bad category. Please choose one of [#{choices}]")

    # Ensure we're using a real tag
    if not config.tags.contains(update.status)
        choices = joinString ", ", config.tags
        throw new UpdateError("Bad status. Please choose one of [#{choices}]")

    # Ensure we have a title
    if not update.title?
        throw new UpdateError("Please provide a title for the update.")

    # Ensure we have a title
    if not update.author?
        throw new UpdateError("Please provide an author for the update.")


prepareTitle = (update, done) ->
    ###
    Prepares a unique title for the update file.
    ###

    counter = 0
    nextTitle = () ->
        ###
        Prepare the file's title, ensuring that it is unique by
        tacking a -1, -2, -3, etc onto the end of the filename.
        ###
        title = "#{update.date.format 'YYYY-MM-DD'}-#{slug update.title}"
        if counter > 0
            title = "#{title}-#{counter}"
        counter += 1
        return "#{title}.md"

    options =
        user: config.repo.owner
        repo: config.repo.name
        path: "_posts"
        ref: "master"

    github.repos.getContent options, (err, result) ->
        if err
            throw new UpdateError("Error getting content: #{err}")

        # Retrieve the file names from `_posts/`
        names = _(result).map((x) -> x.name)

        # Generate titles until we have a unique one.
        title = do nextTitle
        while _(names).contains title
            title = do nextTitle

        # Call the callback when we're done.
        done title


prepareUpdate = (update, done) ->
    ###
    Prepare a title and content for a status update
    ###

    # YAML front matter for post
    frontMatter = yaml.safeDump
        layout: config.layout
        category: update.category
        tags: update.status
        date: update.date.format 'YYYY-MM-DD HH:mm:ss ZZ'

    # Post content
    content = "---\n#{frontMatter}---\n\n#{update.message}\n"

    # Get a unique title
    prepareTitle update, (fileName) ->
        file =
            file:
                name: fileName
                content: content
                base64: new Buffer(content).toString('base64')
        done _.extend(update, file)


submitUpdate = (update, done) ->
    ###
    Submit a status update to GitHub
    ###
    options =
        user: config.repo.owner
        repo: config.repo.name
        path: "_posts/#{update.file.name}"
        message: "Update status of #{update.category} to #{update.status}"
        content: update.file.base64
        branch: "master"

    github.repos.createFile options, (err, result) ->
        if err
            throw new UpdateError("Error creating file: #{err}")
        done result


updateStatus = (msg, update) ->
    ###
    Update a Jekyll status site
    ###

    # Check that our options are OK
    validateUpdate update

    prepareUpdate update, (newUpdate) ->
        submitUpdate newUpdate, (result) ->
            msg.reply "Updated status of #{update.category} to #{update.status}"
            msg.reply "View the commit here: #{result.commit.html_url}"


module.exports = (robot) ->
    # Sanity check our required variables
    unless config.repo.name?
        robot.logger.warning "HUBOT_STATUS_REPO_NAME variable is not set."
    unless config.repo.owner?
        robot.logger.warning "HUBOT_STATUS_REPO_OWNER variable is not set."
    unless config.cred.token?
        robot.logger.warning "HUBOT_STATUS_GITHUB_TOKEN variable is not set."


    robot.respond /update (.*) to (.*); (.+): (.+)$/i, (msg) ->

        unless robot.auth.hasRole msg.envelope.user, config.update_role
            msg.reply "Sorry! You need the #{config.update_role} role to update statuses."
            return

        unless config.repo.name?
            msg.reply "I 'unno what to update. Set HUBOT_STATUS_REPO_NAME."
            return
        unless config.repo.owner?
            msg.reply "I 'unno what to update. Set HUBOT_STATUS_REPO_OWNER."
            return
        unless config.cred.token?
            msg.reply "I can't get to the repo. Set HUBOT_STATUS_GITHUB_TOKEN."
            return

        update =
            date: moment()
            author: msg.message.user.name
            category: msg.match[1]
            status: msg.match[2]
            title: msg.match[3]
            message: msg.match[4]

        try
            updateStatus msg, update
        catch error
            console.log "Encountered an error: #{error.message}"
            msg.reply error.message
