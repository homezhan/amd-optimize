_      = require("lodash")
acorn  = require("acorn")
walk   = require("acorn/util/walk")

valuesFromArrayExpression = (expr) -> expr.elements.map( (a) -> a.value )

module.exports = parseRequireDefinitions = (config, file, callback) ->

  try
    comments = []
    tokens = []
    ast = acorn.parse(
      file.stringContents,
      sourceFile : file.relative
      locations : file.sourceMap?
      ranges: true
      onComment: comments
      onToken: tokens
    )
  catch err
    if err instanceof SyntaxError
      err.filename = file.path
      err.message += " in #{file.path}"
    callback(err)
    return

  file.ast = ast
  file.comments = comments
  file.tokens = tokens

  definitions = []
  walk.ancestor(ast, CallExpression : (node, state) ->

    if node.callee.name == "define"

      switch node.arguments.length

        when 1
          # define(function (require, exports, module) {})
          if node.arguments[0].type == "FunctionExpression" and
          node.arguments[0].params.length > 0

            deps = []
            walk.simple(node.arguments[0], CallExpression : (node) ->
              if node.callee.name == "require" or node.callee.name == "requirejs"
                deps.push(node.arguments[0].value)
            )

        when 2
          switch node.arguments[0].type
            when "Literal"
              # define("name", function () {})
              moduleName = node.arguments[0].value
            when "ArrayExpression"
              # define(["dep"], function () {})
              deps = valuesFromArrayExpression(node.arguments[0])

        when 3
          # define("name", ["dep"], function () {})
          moduleName = node.arguments[0].value
          deps = valuesFromArrayExpression(node.arguments[1])

      definitions.push(
        method : "define"
        moduleName : moduleName
        deps : deps ? []
        node : node
      )

      isInsideDefine = true


    if (node.callee.name == "require" or node.callee.name == "requirejs") and node.arguments.length > 0 and node.arguments[0].type == "ArrayExpression"

      defineAncestors = _.any(
        state.slice(0, -1)
        (ancestorNode) -> ancestorNode.type == "CallExpression" and (ancestorNode.callee.name == "define" or ancestorNode.callee.name == "require" or ancestorNode.callee.name == "requirejs")
      )
      if config.findNestedDependencies or not defineAncestors
        definitions.push(
          method : "require"
          moduleName : undefined
          deps : valuesFromArrayExpression(node.arguments[0])
          node : node
        )

  )

  callback(null, file, definitions)
  return
