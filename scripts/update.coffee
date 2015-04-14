# Description:
#   Posts updates to status.megaminerai.com
#
# Commands:
#   hubot help - Displays all of the help commands that Hubot knows about.
#   hubot help <query> - Displays all help commands that match <query>.
#
# URLS:
#   /hubot/help
#
# Notes:
#   These commands are grabbed from comment blocks at the top of each file.


_ = require "underscore"
git = require "nodegit"
yaml = require "js-yaml"
moment = require "moment"
slug = require "slug"
promisify = require "promisify-node"
fse = promisify(require("fs-extra"))
path = require "path"
tmp = require 'tmp'


class UpdateError
    constructor: (@message) ->


categories = _ ['arena', 'food', 'gameserver', 'git', 'visualizer', 'webserver']
tags = _ ['OK', 'Warning', 'Down']

joinString = (char, _lst) ->
    maybeJoin = (x, y) ->
        if x == ""
            y
        else
            x + char + y
    _lst.reduce maybeJoin, ""

validateOptions = (options) ->
    console.log "Validating options"

    # Ensure we're using a real category
    if not categories.contains(options.category)
        choices = joinString ", ", categories
        throw new UpdateError("Bad category. Please choose one of [#{choices}]")

    console.log "Category OK"

    # Ensure we're using a real tag
    if not tags.contains(options.status)
        choices = joinString ", ", tags
        throw new UpdateError("Bad status. Please choose one of [#{choices}]")

    console.log "Status OK"

    # Ensure we have a title
    if not options.title?
        throw new UpdateError("Please provide a title for the update.")

    # Ensure we have a title
    if not options.author?
        throw new UpdateError("Please provide an author for the update.")

    console.log "Options are valid!"

updateStatus = (msg, tmpPath, content, options) ->

    # Check that our options are OK
    validateOptions options

    layout = 'update'
    date = moment()

    u = do date.unix
    o = do date.utcOffset

    author = git.Signature.create options.author, "siggame@mst.edu", u, o
    committer = git.Signature.create "Gerty", "siggame@mst.edu", u, o

    frontMatter = yaml.safeDump
        layout: layout
        category: options.category
        tags: options.status
        date: date.format 'YYYY-MM-DD HH:mm:ss ZZ'

    fileName = "#{date.format 'YYYY-MM-DD'}-#{slug options.title}.md"
    fileContent = "---\n#{frontMatter}---\n\n#{content}\n"

    repo = null
    index = null
    oid = null

    git.Clone.clone('https://github.com/siggame/status', tmpPath)
        .then (repoResult) ->
            # Save the repo
            repo = repoResult

        .then () ->
            # Write our update file
            posts_dir = path.join repo.workdir(), "_posts"
            filePath = path.join posts_dir, fileName
            fse.writeFile filePath, fileContent

        .then () ->
            # Get the repo's index
            repo.openIndex()

        .then (indexResult) ->
            # Read the index
            index = indexResult
            index.read(1)

        .then () ->
            # Add our file to the index
            filePath = path.join "_posts", fileName
            index.addByPath filePath

        .then () ->
            # Update the index
            index.write()

        .then () ->
            # Create our new tree for the commit
            index.writeTree()

        .then (oidResult) ->
            # Get the reference (hash) for HEAD
            oid = oidResult
            git.Reference.nameToId(repo, "HEAD")

        .then (head) ->
            # Get the HEAD commit
            repo.getCommit(head)

        .then (parent) ->
            # Make the commit!
            m = "Update status for #{options.category}"
            repo.createCommit "HEAD", author, committer, m, oid, [parent]

        .done (ref) ->
            msg.reply "Committed update for #{options.category} (#{ref})"


module.exports = (robot) ->

    robot.respond /update (.*) to (.*); (.+): (.+)$/i, (msg) ->
        options =
            author: msg.message.user.name
            category: msg.match[1]
            status: msg.match[2]
            title: msg.match[3]
        content = msg.match[4]

        console.log options

        tmp.dir (err, path, cleanupCallback) ->
            try
                updateStatus msg, path, content, options
            catch error
                console.log "Encountered an error!"
                msg.reply error.message
            finally
                do cleanupCallback
