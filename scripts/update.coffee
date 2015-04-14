# Description:
#   Generates help commands for Hubot.
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
nodegit = require "nodegit"
yaml = require "yaml"
moment = require "moment"
slug = require "slug"
promisify = require "promisify-node"
fse = promisify(require("fs-extra"))
path = require "path"
tmp = require 'tmp'

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
        throw message: "Bad category. Please choose one of [#{choices}]"

    console.log "Category OK"

    # Ensure we're using a real tag
    if not tags.contains(options.status)
        choices = joinString ", ", tags
        throw message: "Bad status. Please choose one of [#{choices}]"

    console.log "Status OK"

    # Ensure we have a title
    if not options.title?
        throw message: "Please provide a title for the update."

    # Ensure we have a message
    if not options.message?
        throw message: "Please provide a message for the update."

    console.log "Options are valid!"

updateStatus = (tmpPath, content, options) ->

    # Check that our options are OK
    validateOptions options

    layout = 'update'
    date = moment()

    u = do date.unix
    o = do date.offset

    author = nodegit.Signature.create options.author, "siggame@mst.edu", u, o
    committer = nodegit.Signature.create "Gerty", "siggame@mst.edu", u, o

    fontMatter = yaml.safeDump
        layout: layout
        category: options.category
        tags: options.status
        date: date.format 'YYYY-MM-DD HH:mm:ss ZZ'

    fileName = "#{date.format 'YYYY-MM-DD'}-#{slug options.title}"
    fileContent = "---
        #{fontmatter}
        ---

        #{options.message}
        "
    repo = null
    posts_dir = null
    index = null
    oid = null

    Clone.clone('https://git@github.com:siggame/status', tmpPath)
        .then (repoResult) ->
            repo = repoResult
            posts_dir = path.join repo.workdir(), "_posts"

        .then () ->
            filePath = path.join posts_dir, fileName
            fse.writeFile filePath, fileContent

        .then () ->
            repo.openIndex()

        .then (indexResult) ->
            index = indexResult
            index.read(1)

        .then () ->
            # this file is in a subdirectory and can use a relative path
            filePath = path.join "_posts", fileName
            index.addByPath filePath

        .then () ->
            index.write()

        .then () ->
            index.writeTree()

        .then (oidResult) ->
            oid = oidResult
            nodegit.Reference.nameToId(repo, "HEAD")

        .then (head) ->
            repo.getCommit(head)

        .then (parent) ->
            msg = "Update status for #{options.category}"
            repo.createCommit "HEAD", author, committer, msg, oid, [parent]

        .done (commitId) ->
            console.log "New Commit: ", commitId


module.exports = (robot) ->

    robot.respond /update (.*) to (.*): (.*): (.*)$/i, (msg) ->
        options =
            category: msg.match[1]
            status: msg.match[2]
            title: msg.match[3]
        content = msg.match[4]

        try
            tmp.dir (err, path, cleanupCallback) ->
                updateStatus path, content, options
                do cleanupCallback
        catch error
            console.log "Encountered an error!"
            msg.reply error.message
